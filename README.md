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

The `/_cat/indices API` returns a `pri` (primary) and a `rep` (replicas) column. This indicates how many shards an index has.

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

Examples:

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



