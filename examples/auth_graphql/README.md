# Auth GraphQL example

The [auth example](../auth)'s users, organizations and sessions, served only as GraphQL. There is one route, `POST /graphql`, and no REST endpoints.

It's read-only for now: GraphQL mutations aren't built yet, so logging in and creating records come from `db/seeds.rb`.

## Running it

```bash
bundle install
bin/rails db:prepare        # creates and seeds the database; prints an application token and a session token
bin/rails server
bundle exec rspec
```

In development, open `localhost:3000/graphiql` to explore the schema. Put a token in the Headers tab first, e.g. `{ "X-Application-Token": "app_..." }`.

## Layout

```
app/controllers/application_controller.rb   # who the caller is: application or session token
app/controllers/graphql_controller.rb       # POST /graphql: graphql_resources Resources::UsersController, ...
app/graphql/resources/                      # the resources: schema, search, pagination, scope, before_actions
schema.graphql                              # the generated schema, kept current by a spec (rails graphql:dump)
```

The resources are SchemaApi controllers with no routes. Each one becomes a type and two query fields:
- **The type:** its schema.
- **The arguments:** `search` and `paginate` define each list field's `filter`, `sort` and paging arguments.
- **Who sees what:** `before_action :authenticate!` and `resource_scope` decide it, exactly as they would over REST.

## Queries

```bash
curl -X POST localhost:3000/graphql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"query":
  "{ users { nodes { name affiliations { organization { name } affiliation_attributes { title manager_user { name } } } } } session(id: \"current\") { expires_at } }"}'
```

| Field | Who | Returns |
|---|---|---|
| `users(filter:, sort:, limit:, cursor:, page:, count:)`, `user(id:)` | applications: everyone; users: people in their organizations | users with affiliations, organization-level details and managers |
| `organizations(...)`, `organization(id:)` | applications: all; users: their own | organizations with `member_count` |
| `sessions(...)`, `session(id:)` | users only | the caller's active sessions; `session(id: "current")` is this one |

## Compared with the REST example

- **The resource definitions are the same.** The schemas, searches and scopes are the auth example's, without its REST-only parts (upsert keys, bulk, and the write hooks, which will come back with mutations).
- **`input:` and `write_only:` still matter.** They have no effect on queries, but they're the contract mutations will accept. `password` is write-only, so it isn't in the schema.
- **Organization members aren't exposed separately.** REST nests them under `/organizations/:id/members`. Here a user's `affiliations` already give that view, and GraphQL doesn't support nested-route resources yet.
- **Errors don't change the status code.** A field the caller may not read is `null`, with an error whose `extensions` carry `code` (`unauthorized`, `not_found`, ...), `status` and `details`, and the rest of the query still returns data.
