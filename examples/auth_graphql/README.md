# Auth GraphQL example

The [auth example](../auth)'s users, organizations and sessions, served only as GraphQL. There is one route, `POST /graphql`, and no REST endpoints. Logging in, logging out and managing users and organizations are all mutations.

## Running it

```bash
bundle install
bin/rails db:prepare        # creates and seeds the database; prints an application token and a session token for Ada
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

The resources are SchemaApi controllers with no routes. Each one becomes an object type, an input type, query fields and mutations:
- **The types:** the schema. Rendered fields make the object type; writable fields make the input type.
- **The arguments:** `search` and `paginate` define each list field's `filter`, `sort` and paging arguments.
- **The mutations:** one per action the resource has: `create_*`, `update_*`, `upsert_*` (with `upsert_key`) and `delete_*`.
- **Who may do what:** `before_action`s, `resource_scope` and the write hooks decide it, exactly as they would over REST.

## Logging in

```bash
curl -X POST localhost:3000/graphql -H 'Content-Type: application/json' -d '{"query":
  "mutation { create_session(session: { email: \"ada@example.com\", password: \"secret-password\" }) { token expires_at } }"}'
```

`token` is only filled in on `create_session`. Send it as `Authorization: Bearer <token>`. `delete_session(id: "current")` logs out.

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

## Mutations

| Mutation | Who | Notes |
|---|---|---|
| `create_session`, `delete_session` | anyone with a valid login; users | log in and out |
| `create_user`, `upsert_user` | applications | `upsert_user` matches by `email`, for imports |
| `update_user`, `delete_user` | applications; a user for their own account | only applications change `affiliations`; a new `password` ends the user's other sessions; delete is soft and ends sessions |
| `create_organization`, `update_organization`, `upsert_organization`, `delete_organization` | applications | the creating application is recorded; `slug` is create-only |

```graphql
mutation($user: UserInput!) {
  create_user(user: $user) { id affiliations { organization { slug } affiliation_attributes { title } } }
}
# variables: { "user": { "name": "Linus", "email": "linus@example.com", "password": "secret-password",
#                        "affiliations": [{ "organization_id": 1, "affiliation_attributes": { "title": "Lead" } }] } }
```

`update_*` changes only the fields that are sent, and a field sent as `null` is cleared. Nested items are matched by their key (`organization_id` for affiliations), and `_destroy: true` removes one. A failed mutation is `null`, with its error's `code` (`validation_error`, `forbidden`, `stale_resource`, ...), `status` and `details` in `extensions`. Field paths look like `affiliations[0].affiliation_attributes.title`.

## Compared with the REST example

- **The resource definitions are the same.** The schemas, searches, scopes and write hooks are the auth example's. Bulk is left out: aliasing several mutations in one request does the same job, each in its own transaction.
- **`input:` and `write_only:` make the input types.** `password` is write-only, so it's on `UserInput` but not on `User`.
- **Organization members aren't exposed separately.** REST nests them under `/organizations/:id/members`. Here a user's `affiliations` already give that view, and GraphQL doesn't support nested-route resources yet.
- **Errors don't change the status code.** A field the caller may not read or write is `null`, with an error whose `extensions` carry `code` (`unauthorized`, `not_found`, ...), `status` and `details`. The rest of the request still runs.
