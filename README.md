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





## Section 5: Searching

 * [Search API](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html)
 * [Query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)


### Term level queries

[term level queries](https://www.elastic.co/guide/en/elasticsearch/reference/current/term-level-queries.html) are used for exact queries (enums, IP & email addresses, ..)
 
They can be used with several data types like `keyword`, `long`, `date`, `boolean`, .. (but NOT with `text`).

The search terms of term level queries are not analyzed.

#### Examples

* [term[s]](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/searching-for-terms.md)
* [ids](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/retrieving-documents-by-ids.md)
* [range](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/range-searches.md)
* [prefix/wildcard/regex](https://github.com/codingexplained/complete-guide-to-elasticsearch/tree/master/Searching%20for%20Data)
  * don't do term level queries with wildcards in the beginning (for the same reason that you don't do `like '%term'` SQL queries)
  * Elasticsearch uses Apache Lucene's [regular expression syntax](https://www.elastic.co/guide/en/elasticsearch/reference/current/regexp-syntax.html)
  * these 3 query types support a parameter `"case_insensitive": true`
* [exists](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/querying-by-field-existence.md)
  * Only missing fields and fields with value `null` or `[]` or considered missing. Value `""` is considered existing.
  * NB: If a `null_value` parameter was specified for a field, field instances with this `null_value` value are considered existing !!!
  * when the `index` mapping parameter is set to `false` teh `exists` query will also yield no result
  * same for [`ignore_above`](https://www.elastic.co/guide/en/elasticsearch/reference/current/ignore-above.html) and [`ignore_malformed`](https://www.elastic.co/guide/en/ elasticsearch/reference/current/ignore-malformed.html)
  * the inverse (exists not) has no dedicated query; you must a `bool` query with `must_not` to achieve that

### Full text queries

[full text queries](https://www.elastic.co/guide/en/elasticsearch/reference/current/full-text-queries.html)

* are analyzed (term level queries are not)
* should not be applied on `keyword` fields (because those were not analyzed, and for instance not lowercased)

#### Examples

* [match](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/the-match-query.md)
* [multi_match](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/searching-multiple-fields.md)
  * [Reference](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-multi-match-query.html)
  * the default type is `best_fields` which means that the result will be ordered by the relevance score of the field with the highest score within a document; you can use a [tie-breaker](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-multi-match-query.html#type-best-fields) if you want to (partially) include the score of other matching fields as well.
* [match_phrase](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/phrase-searches.md)
  * [Reference](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query-phrase.html)
  * used to find exact phrases within unstructured text; Elasticsearch stores term positions in the inverted index to support this

### Relevance scoring

[Relevance tuning](https://www.elastic.co/guide/en/app-search/current/relevance-tuning-guide.html)

### Compound queries

All the above queries are so-called _leaf queries_. 

A [compound query](https://www.elastic.co/guide/en/elasticsearch/reference/current/compound-queries.html) wraps other compound queries and/or leaf queries.

An example is the [bool](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html) query. It can have the following clauses:
* `must`: must appear in matching documents
* `should`: 
  * if used together with other type of clauses, a matching `should` contributes to the score, but the should-clause is not required to match
  * if the `bool` query only contains `should` clauses, at least of them __must__ match
  * use `minimum_should_match` parameter to specify how many of the `should` clauses should match for a document to be returned
* `must_not`: 
* `filter`: like `must` but ignores relevance scores
  * makes sense: you first filter out irrelevant documents (and do not care yet about the score of what remains) and then use other query clauses (`must`, `should`, ..) to sort the remaining documents
  * improves performance

[examples](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/querying-with-boolean-logic.md)

### Nested queries

[nested fields](https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html) (arrays of objects) can only be queried with a [nested query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-nested-query.html). If you try to query nested fields with an ordinary `bool` or `match` query or whatever, it will yield unpredictable results!

Examples
* [nested](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/querying-nested-objects.md)
* [nested / inner_hits](https://github.com/codingexplained/complete-guide-to-elasticsearch/blob/master/Searching%20for%20Data/nested-inner-hits.md)
  * includes an extra `inner_hits` object containing a list with all the nested objects that matched the query.

And
* An index can contain max. 50 nested fields (this max. can be increased with index.mapping.nested_fields.limit).
* A document can contain max. 10,000 nested documents (across all nested fields) to prevent OOM errors.






## Section 6: Joining queries

Elasticsearch is not optimized for joining data like relational database. It does offer some simple join functionality.

Scroll to the end of this chapter (terms lookup mechanism) for cross-index joins...

### Defining a relationship mapping

You can define a parent-child relationship between documents in an index by creating a [field of type `join`](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/parent-join.html).

For example, the following means that a department can have multiple employees:
```
PUT department/_mapping
{
  "properties": {
    "join_field": {
      "type": "join",
      "relations": {
        "department": "employee"
      }
    }
  }
}
```

Or multiple employees and multiple locations:
```
"relations": {
  "department": ["employee", "location"]
} 
```

__NB: The name `join_field` is arbitrary. We could have chosen any other name. The only thing that matters is `"type": "join"`.__

### Adding parent documents

You must specify in the `join_field` what type of document you're adding:

```
POST department/_doc/101
{
  "name": "Research",
  "join_field": {
    "name": "department"
  }
}
```

Or (short form):
```
POST department/_doc/102
{
  "name": "Development",
  "join_field": "department"
}
```

### Adding child documents

In addition to specifying the child type in the `join_field` we must also specify query parameter `?routing=parent_id` to ensure that the child document is stored in the same shard as its parent.

```
POST department/_doc/101001?routing=101
{
  "name": "Jane",
  "join_field": {
    "name": "employee",
    "parent": "101"
  }
}

POST department/_doc/102001?routing=102
{
  "name": "John",
  "join_field": {
    "name": "employee",
    "parent": "102"
  }
}
```

### Return child documents based on parent id

Return child documents with a query of type [`parent_id`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-parent-id-query.html):

```
GET department/_search
{
  "query": {
    "parent_id": {
      "type": "employee",
      "id": "101"
    }
  }
}
```

### Return child documents based on parent query

Return child documents with an arbitrary query on the parent with [`has_parent`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-has-parent-query.html):

```
GET department/_search
{
  "query": {
    "has_parent": {
      "parent_type": "department",
      "query": {
        "match": {
          "name": "Development"
        }
      }
    }
  }
}
```

### Return parent documents based on child query

The opposite direction with [`has_child`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-has-child-query.html)

```
GET department/_search
{
  "query": {
    "has_child": {
      "type": "employee",
      "score_mode": "sum", 
      "query": {
        "match_phrase_prefix": {
          "name": "Jo"
        }
      }
    }
  }
}
```

### Multi-level relations

```
PUT company/_mapping
{
  "properties": {
    "join_field": {
      "type": "join",
      "relations": {
        "company": "department",
        "department": "employee"
      }
    }
  }
}
```

### Terms lookup mechanism (cross index searching)

The terms lookup mechanism is the only mechanism to join across different indices.

Consider an entity `site`. Sites can be grouped into `collection`s. A collection can contain many sites, and one site can be in many collections.

Suppose a `collection` has a field `sites` which is an array holding its site ids. Then you can lookup a collection's sites in the `sites` index as follows:

```
GET sites/_search
{
  "query": {
    "terms": {
      "id": {
        "index": "collections",
        "type": "_doc",
        "id": COLLECTION_ID,
        "path": "sites"
      }
    }
  }
}
```

__NB: the site document has no knowledge of collections.__
__NB2: the default limit for the number of terms is 65.000.__


### Resources

 * [Udemy examples](https://github.com/codingexplained/complete-guide-to-elasticsearch/tree/master/Joining%20Queries)
 * [mapping `join` fields](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/parent-join.html)
 * [joining queries](https://www.elastic.co/guide/en/elasticsearch/reference/current/joining-queries.html) (`parent_id`, `has_parent` and `has_Child`)
 * [terms lookup mechanism](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/query-dsl-terms-query.html#query-dsl-terms-lookup)





## Section 7: Controlling query results (sorting, paging)

In the [common options](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/common-options.html) section you can find several options to control / filter / format the output of the Elasticsearch API.

Below we discuss some of them.

### Source filtering with `_source`

You can specify what fields from the `_source` document you want returned with the [`_source`option](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/search-fields.html#source-filtering):

```
GET departments/_search
{
  "_source": false
  "query": {
    "match": {
      ...
    }
  }
}
```

or, using "includes" and "excludes":

```
GET departments/_search
{
  "_source": {
    "includes": "employees.*",
    "excludes": "employees.name"
  }
  "query": {
    "match": {
      ...
    }
  }
}
```

### Response filtering with `filter_path`

[Response filtering](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/common-options.html#common-options-response-filtering) can be used to reduce the response size.

```
GET recipes/_search?filter_path=took,hits.hits._id,hits.hits._score
{
  "query": {...}
}
```

### Implementing paging / pagination

#### Search API `from` and `size`

The [search API](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/paginate-search-results.html) offers `from` and `size` query parameters.

This example returns the 3rd page (of size 20):

```
GET /_search
{
  "from": 40,
  "size": 20,
  "query": {
    "match": { ... }
  }
}
```

or

```
GET /_search?size=20&from=40
{
  "query": {
    "match": { ... }
  }
}
```

__NB1: By default, you cannot use from and size to page through more than 10,000 hits. If you need to page through more than 10,000 hits, use `search_after`.__

Deep paging consumes a lot of memory! 

__NB2: Elasticsearch uses Lucene’s internal doc IDs as tie-breakers. These internal doc IDs can be completely different across replicas of the same data. When paging search hits, you might occasionally see that documents with the same sort values are not ordered consistently.__

#### Search after

When you specify a `sort` in your query, each document will be assigned a sort value. Sorting is based on this sort value, and the sort value is included in the response in the `sort` field.

Instead of paging using `from`, you can use the [search_after](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/paginate-search-results.html#search-after) element. In the `search_after` field you specify the sort values from the last hit from the previous page. Example:

```
GET twitter/_search
{
    "query": {
        "match": {
            "title": "elasticsearch"
        }
    },
    "search_after": [1463538857, "654323"],
    "sort": [
        {"date": "asc"},
        {"tie_breaker_id": "asc"}
    ]
}
```


#### Sorting

[Sorting search results](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/sort-search-results.html)

The default sort order is by relevance score. This is equivalent to `"score": "_score"`.

You can sort on multiple fields (and even use the relevance score as secondary sort order):

```
GET /my-index-000001/_search
{
  "sort" : [
    { "name" : "asc" },
    { "age" : "desc" },
    "_score"
  ],
  "query" : {
    "term" : { ... }
  }
}
```

Special sort fields:
 * `_score` : relevance score
 * `_doc`: index order

Ordering by `_doc` has no real use cases (the order within an index is meaningless) but it could be used as a secondary order to achieve reliable pagination (?).

#### Sorting on multi-valued fields

You can also sort on fields that can contain multiple values.

You can specify with the [sort `mode`](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/sort-search-results.html#_sort_mode_option) how to calculate the sort value of a multi-valued field. Possible modes:
 * `min`
 * `max`
 * `sum`
 * `avg`
 * `median`

For example, for `"field": ["A", "Z"]` with mode `max`, it will use the "Z" for sorting.

And for `"field": [0.0, 100.0]` with mode `avg` it will use `50.0` for sorting.






