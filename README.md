# elasticsearch-course

My notes of the Udemy course 'Complete Guide to Elasticsearch'

## Section 2: Getting started

 * ELK Stack: Elastic / Logstash / Kibana
 * Elastic Stack: ELK Stack + Beats / X-Pack.

General information about [clusters](https://www.elastic.co/guide/en/elasticsearch/reference/current/high-availability.html) and [nodes](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html).

### Kibana and Elasticsearch installation with Docker Compose

Follow [this manual](https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#docker-compose-file) to install an Elasticsearch cluster with Docker Compose.

 Kibana runs on [localhost:5611](http://localhost:5611).
 * User: `elastic` 
 * Password: [`ELASTIC_PASSWORD`](./docker/.env)

### Sharding and Replication

#### Sharding

Large indices will not fit on a single node. Sharding allows for _horizontal scalability_ of an index.

Sharding is _specified at the index level_. The default number of shards is 1. 

You can not simply add an extra shard to an existing index. This search algorithm will then fail to find documents (see the section on routing below). Use the _Split_ or _Shrink_ API to increase or decrease the number of shards of an existing index.

The `/_cat/indices` API returns a `pri` (primary) and a `rep` (replicas) column. This indicates how many shards an index has.

#### Replication

Replication can be used for fault tolerance / failover / increased throughput.

Replication is _specified at shard level_. Replication is enabled by default. On a single node cluster it will have no effect, but the `auto_expand_replicas=1` setting ensures that a replica is added as soon as a second node is added to the cluster.

The _primary shard_ together with its _replica shards_ are called a _replication group_.

It is possible to add multiple replica shards (for the same primary) on the same node, to increase throughput (it allows for executing more queries in parallel).

#### Snapshots

Elastic takes a _snapshot_ before executing 'update by query' operations.

You can also take a snapshot manually. This is recommended before doing document transformations / migrations.

### Creating an index

```
PUT /my-index
GET /_cat/indices?v
GET /_cat/shards?v
```

NB: On a single node cluster the health of this index (and the cluster itself) will be yellow: Elasticsearch was unable to assign a node to the replica shard. As soon as you add a second node, the replica shard will be assigned to the node and the health will become green.

### Querying

 * [API Reference](https://www.elastic.co/guide/en/elasticsearch/reference/current/rest-apis.html)
    * [Cluster API](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster.html)
    * [CAT API](https://www.elastic.co/guide/en/elasticsearch/reference/current/cat.html)
      * use `?v` to add column headers
      * use `?format=json` for json instead of tabular output
      * use `?s=field:asc` to sort the output by field
      * example: `GET /_cat/indices?v&format=json&s=index:desc&expand_wildcards=all`
 * [Query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)

You can access the Elasticsearch API in Kibana via Management / Dev Tools or with an http client (Postman, cUrl).

A cUrl example is the [import-products.zsh](./resources/section-3/import-products.zsh) script.

Benefits of using Kibana:
 * autocomplete
 * automatic HTTP headers
 * formatted output

## Section 3: Managing Documents

 * Course examples [in GitHub](https://github.com/codingexplained/complete-guide-to-elasticsearch/tree/master/Managing%20Documents)
 * [Document API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs.html)

### Creating an index

```
PUT /products
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 2"
  }
}
```

### Indexing documents

Auto-generate Document Id:
```
POST /products/_doc
{
  "type": "TV",
  "brand": "Philips",
  "price": 250.00,
  "in_stock": 10
}
```

Manually assign Document Id:
```
PUT /products/_doc/101
{
  "type": "TV",
  "brand": "SONY",
  "price": 399.00,
  "in_stock": 6
}
```

You can do partial updates of a document.
In this case update the stock field from 6 to 5:
```
POST /products/_update/101
{
  "doc": {
    "in_stock": 5
  }
}
```

You can use a scripted update:
```
POST /products/_update/101
{
  "script": {
    "source": "ctx._source.in_stock--"
  }
}
```

### Querying documents 

Single document:
```
GET /products/_doc/101
```

All documents:
```
GET /products/_search
{
  "query": {
    "match_all": {}
  }
}
```

### More examples

 * [upsert](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/upserts.md)
 * [replace](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/replacing-documents.md)
 * [update by query](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/update-by-query.md)
   * not transactional (update can partially succeed)
   * use `?conflicts=proceed` to proceed instead of abort on version number conflicts (default behavior is abort on first failure)
 * [delete by query](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/delete-by-query.md)
 * [bulk updates](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/batch-processing.md) ([example](./resources/section-3/import-products.zsh))

API documentation:

 * [Update by Query API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html)
 * [Bulk API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html)

### Routing 

Routing is the process of resolving the shard for a document. The default routing strategy uses a simple formula:

`shard_num = hash(_routing) % num_primary_shards`

The `_routing` in the above formula references a document field (just like `_id`, `_source`, etc).

In case of the default routing strategy, the `_id` field is used for routing, and the `_routing` field is absent.

A result of the fact that the number of shards is used in the routing algorithm is that we can not change number of shards of an existing index. The formula would yield different results for existing documents, so we won't be able to find them back.

### Primary term

When the primary shard fails, another shard will become the new primary shard. To avoid data loss when this happens, elastic adds certain metadata to its operations. The response of an `_update` operation may look like this:

```
{
  "_index": "products",
  "_id": "101",
  "_version": 8,
  "_seq_no": 13,
  "_primary_term": 1,
  "found": true,
  "_source": {
    ...
  }
}
```

* `_primary_term` is the sequence number of the primary shard (it increases when a new primary shard is elected).
* `_seq_no` is an operation sequence number. This allows elastic to detect gaps.

Elasticsearch uses checkpoints to keep track of the point up to which all shards have been aligned:
 * A replication group has a _global_ checkpoint (sequence number that all active shards have been aligned up to).
 * A replica shard has a _local_ checkpoint (sequence number of the last write operation performed on that shard).

### Optimistic concurrency control

Optimistic concurrency control can be realized using the `_seq_no` and `_primary_term` fields.

This [example](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Managing%20Documents/optimistic-concurrency-control.md) illustrates how to use the `if_primary_term` and `if_seq_no` query parameters.

This form of optimistic locking is used by elasticsearch when it performs an [Update by Query](elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html) (which works by first taking a snapshot, and then updating the documents one by one).



## Section 4: Mapping & Analysis

### Analyzers

This section only applies to fields of type `text`.

An [Analyzer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analyzer.html) contains zero or more character filters and one tokenizer.

A [Character Filter](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-charfilters.html) preprocesses a stream of characters before it is passed to the tokenizer. For instance to [strip HTML](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-htmlstrip-charfilter.html).

A [Tokenizer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-tokenizers.html) splits the text into words (and possibly removes characters like punctiation and whitespace) and stores each token's offset.

A [Token Filter](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-tokenfilters.html) can add, remove or modify tokens. Example: lowercase

The [Analyze API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-analyze.html) performs [analysis](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis.html) on a text string and returns the resulting tokens.

Here is a [list of built-in analyzers](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-analyzers.html).

#### Standard Analyzer

Three ways of performing an analysis with the standard analyzer:

```
POST /_analyze
{
  "text": "3 traveling   PIGS...in a brwon café!"
}
```

```
POST /_analyze
{
  "text": "3 traveling   PIGS...in a brwon café!",
  "analyzer": "standard"
}
```

```
POST /_analyze
{
  "text": "3 traveling   PIGS...in a brwon café!",
  "char_filter": [],
  "tokenizer": "standard",
  "filter": ["lowercase"]
}
```

The resulting tokens are `["3", "traveling", "pigs", "in", "a", "brwon", "café"]`.

#### Custom analyzers

 * [configure a custom analyzer](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Mapping%20%26%20Analysis/creating-custom-analyzers.md) during index creation
 * [add an analyzer to an existing index](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Mapping%20%26%20Analysis/adding-analyzers-to-existing-indices.md)
   * The analyzer is a [static setting](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules.html) of the index. Static settings can only be changed on a [closed index](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-close.html) (one that blocks read & write operations). You can close an index as follows:
    * `POST /my-index/_close`
    * `POST /my-index/_open`
 * [update an existing analyzer](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Mapping%20%26%20Analysis/updating-analyzers.md)

__Make sure to reindex all document when you update an analyzer:__ `POST /my-index/_update_by_query?conflicts=proceed`. Otherwise half of your documents were indexed using the old analyzer, and the other half with the new analyzer. This may yield unpredictable search results.

#### Inverted Indices

An inverted index is a mapping between terms (i.e. tokens) and which documents contain them. They store 
 * terms
 * document Ids
 * relevance

Each `text` field has a dedicated inverted index.

NB: numeric, date and geospatial fields use BKD trees instead of inverted indices.

### Mappings

Defines the structure of documents: 
 * fields 
 * [data types](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html).
 * index configuration

#### Coercion

[coercion](https://www.elastic.co/guide/en/elasticsearch/reference/current/coerce.html) is enabled by default. You can configure an index or field to disable coercion.

#### Dynamic mapping

With dynamic mapping, the field type in the first indexed document determines the data type that will be registered in the mapping: `"price": "7.50"` will cause the `price` field to be mapped as a `string`. 

NB: even though the initial `"7.50"` represents a numeric value, it will not be automatically coerced into a float.

Whenever you index a new document that contains a `price` in a different format (e.g. `"price": 7.50`) it will be coerced into the original data type (in this case `string`).

##### Configuring dynamic mapping

You can disable dynamic mapping (at the index level or field level).

By defining an explicit mapping for field X, and disabling dynamic mapping for the entire index, any other field Y, Z, .. will be excluded from indexing.

```
POST /people
{
  "mappings": {
    "dynamic": false, 
    "properties": {
      "first_name": {
        "type": "text"
      }
    }
  }
}
```

So those fields will still be part of the `_source` document, but you will just not be able to search, aggregate, sort on it.

Possible `dynamic` values:
 * true (default)
 * false
 * "strict" (Elastic will reject documents with unmapped fields)

##### Dynamic templates

With [dynamic templates](https://www.elastic.co/guide/en/elasticsearch/reference/current/dynamic-templates.html) you can override the default dynamic mapping behavior based on field naming conventions ([example](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Mapping%20%26%20Analysis/dynamic-templates.md#using-match-and-unmatch)).

#### Explicit mapping

[Explicit mapping](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/explicit-mapping.html) is defined by the user on index creation time:

```
PUT /books
{
  "mappings": {
    "properties": {
      "title":             { "type": "text" }, 
      "publisher.name":    { "type": "keyword" }, 
      "publisher.address": { "type": "text" }, 
      "author":    { 
        "properties": {
          "name":         { "type": "text" }, 
          "email":        { "type": "keyword" },
        }
      }
    }
  }
}
```

Notice how you can combine nested documents and dot-notation.

You can also [add a field to an existing mapping](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/explicit-mapping.html#add-field-mapping).

#### Mapping Recommendations

 * To avoid unexpected behavior: 
   * use explicit mapping and set `"dynamic": "strict"`
   * disable coercion
 * To save disk space
   * when possible, choose between `text` and `keyword`, not both (the default dynamic behavior)
   * set `"doc_values": false"` is you don't need sorting, aggregations and scripting on a field
   * set `"norms": false` if you don't need relevance scoring for a field 
   * set `"index": false` if you don't need to filter on a field


#### Retrieve mapping

```
GET /books/_mapping
GET /books/_mapping/field/author
GET /books/_mapping/field/author.email
```

#### `object` and `nested` data types

The `object` data type is used for nested documents. Apache Lucene (underlying Elasticsearch) does not support. In Apache Lucene nested properties are transformed to dot-notation.

Use the [`nested` data type](https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html) if your document contains arrays of objects. To query `nested` fields you must use a [`nested` query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-nested-query.html).

`nested` objects are stored as hidden documents in Lucene. If you index a document with an array of 10 nested objects, 11 documents will be indexed in total.

#### `keyword` data type

Used for
 * exact matching (e.g. enums)
 * filtering
 * aggregation
 * sorting
 
You can customize the `keyword` analyzer to use the `lowercase` token filter to transform keywords to lowercase.
This is useful if you want to perform case-insensitive exact matches (example: email address).

For full test searches you must use the `text` data type.

The `keyword` analyzer is a no-op analyzer: It ouputs the unmodified string as a single token.

#### No `array` data type

Elastic does not know an array data type: For a field `tags` of type `string`, both `"tags": "Smartphone"` and `"tags": [ "Smartphone", "Electronics" ]` are valid.

#### mapping parameters

With [mapping parameters](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/mapping-params.html) you can configure field mappings.

 * `doc_values`
   * The inverted index is used for queries.
   * The [doc_values](https://www.elastic.co/guide/en/elasticsearch/reference/current/doc-values.html) is another data structure (per index) that is used for aggregation, scripting and sorting. Enabled by default.
   * If you have a large index and you don't need aggregation or sorting for it, consider disabled its `doc_values` to save disk space. It can be specified at field level.
   * Caution: Changing the `doc_values` parameter requires all documents to be reindexed!
 * `norms`
   * The `norms` mapping parameter is used for relevance scoring. Enabled by default.
   * You can disable `norms` for fields that are not part of relevance scoring to save disk space.
 * `index`
   * The `norms` mapping parameter specifies if a field should be indexed. Enabled by default.
   * You can disable `norms` if you don't want to search on a field. The field will still be part of the `_source`. And you can still aggregate and sort on the field.
 * `null_value`
   * Null values can not be indexed or searched in Elasticsearch. If you want to be able to search or index them, specify a `null_value` (i.e. a replacement of the null value indicating that it's null).
 * `copy_to`
   * Allows you to copy multiple fields into a new 'group' field (for instance `full_name` based on `first_name` and `last_name`).

### Reindexing documents with the Reindex API

It is not possible to update existing mappings. The reason is that different data types generally require a different underlying data structure (for instance `text` ends up in an inverted index while numeric fields are indexed into a BKD tree).

If you want to change the data type of a field, you can use the [Reindex API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-reindex.html). 

 * Step 1: Get the original mappings: `GET /products/_mappings`
 * Step 2: Create the new index: `PUT /products_new`
   * add the `"mappings: { ... }"` from the original index to the new index, with the modified data type(s).
 * Step 3: Use the Reindex API: 
    ```
    POST /_reindex
    {
      "source": {
        "index": "products"
      },
      "dest: {
        "index": "products_new"
      },
      "script": {
        "source": """
          if (ctx._source.some.field != null) {
            // do something with some.field
          }
        """
      }
    }
    ```

You can also use the `reindex` API to remove fields from documents. You do this by specifying the fields that should be copied from the source to the target index:
```
POST /_reindex
{
  "source": {
    "index": "products",
    "_source": ["product_id", "brand", "model"]
  },
  "dest: {
    "index": "products_new"
  }
}
```

NB: The destination index of a `_reindex` need not be empty. We can reindex documents into an existing non-empty index.

If you want to reindex millions of documents at once, check the documentation for things like [throttling](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-reindex.html#docs-reindex-throttle) and slicing to limit performance impact.

### Aliases

If you want to rename a field but you don't want to reindex all documents, you can define an [alias](https://www.elastic.co/guide/en/elasticsearch/reference/master/aliases.html).

Besides field aliases, Elasticsearch also support index aliases.

### Multi-field mappings

If you want to field to be searchable (`text`) and aggregate on it (`keyword`) at the same time, you need to map it to two data types at the same time.

```
PUT /recipes
{
  "mappings": {
    "properties": {
      "description" {
        "type": "text"
      },
      "ingredients": {
        "type": "text",
        "fields": {
          "keyword_ix": {
            "type": "keyword"
          }
        }
      }
    }
  }
}
```

In this example an additional inverted index named `ingredients.keyword_ix` is created. This index contains the ingredients unmodified values (not lowercased) and is suitable for exact matching and sorting.

### ECS

ECS or the [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/ecs-reference.html) is an open source specification that defines a common set of fields to be used when storing event data in Elasticsearch, such as logs and metrics.

An example are the [Geo Fields](https://www.elastic.co/guide/en/ecs/current/ecs-geo.html).

ECS is used across the Elastic Stack. But it provides fields only for events. For non-events (regular application data like products, employees, etc.) it is not recommended to use ECS (but you could).

### Stemming 

[Stemming](https://www.elastic.co/guide/en/elasticsearch/reference/current/stemming.html) brings back a word to its root form to make it searchable.

Regular verbs and nouns are easy to stem (bottles -> bottle, walked -> walk).

For irregular verbs and nouns you may need to configure additional dictionary stemmers.

### Stop words

[Stop words](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-stop-tokenfilter.html) are words that have no value for relevance scoring.

























If we want the following search terms to match the above sentence:

 * three -> 3
 * travelling (British) -> traveling (US)
 * pigs -> PIGS
 * brwon -> brown ([fuzzy](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/query-dsl-fuzzy-query.html))
 * cafe -> café! (diacritics, punctuation)





      
