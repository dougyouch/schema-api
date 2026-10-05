# Roles example

Shared roles and permissions for other services, built with SchemaApi: which users have which roles in which organizations, and what those roles allow. Users and organizations live in the auth service, so `user_roles.user_id` and `organization_id` are plain ids here. Models come from `db/schema.rb` through [dynamic-active-model-rails](https://github.com/dougyouch/dynamic-active-model), with `has_many_through` for `Role#permissions`.

The service sits behind a gateway that has already checked the caller's session and passes the acting user's id in `X-User-Id`. Writes require it and record it.

## Running it

```bash
bundle install
bin/rails db:prepare
bin/rails server
bundle exec rspec
```

## Endpoints

```bash
# a service registers its permission catalog; matched by resource + action, so it's safe to repeat
curl -X PUT localhost:3001/permissions/bulk_upsert -H 'X-User-Id: 1' -H 'Content-Type: application/json' -d '{
  "permissions": [{"resource": "cars", "action": "read", "name": "View cars"},
                  {"resource": "cars", "action": "write", "name": "Edit cars"}]}'

# a role from permission ids
curl -X POST localhost:3001/roles -H 'X-User-Id: 1' -H 'Content-Type: application/json' \
  -d '{"role": {"name": "fleet_manager", "permission_ids": [1, 2]}}'

# give user 2 that role in organization 1
curl -X PUT localhost:3001/user_roles/upsert -H 'X-User-Id: 1' -H 'Content-Type: application/json' \
  -d '{"user_role": {"organization_id": 1, "user_id": 2, "role_id": 1}}'

# may user 2 edit cars in organization 1, and which roles allow it?
curl "localhost:3001/authorize?organization_id=1&user_id=2&resource=cars&action=write"

# everything user 2 may do in organization 1
curl localhost:3001/organizations/1/users/2/permissions
```

## What it shows

- **Value lists and computed output** (`RolesController`): `permission_ids` is a plain list of ids stored as `role_permissions` rows (`values_of:`), and `permissions` renders the full objects.
- **Composite upsert keys**:
  - Permissions match by `[resource, action]`, so a service can re-register its whole catalog with one `bulk_upsert`.
  - User roles match by `[organization_id, user_id, role_id]`.
- **Custom filters**: `GET /roles?permission=cars:write` finds the roles that grant a permission.
- **Server-set fields**: `creator_id` and `updated_by_user_id` are read-only in the schema, so a client sending them is ignored. A `before_save` hook fills them from `X-User-Id`.
- **Controller validations**: `validate_input` stops users from changing their own roles and names permission ids that don't exist, alongside schema validations in one `422`.
- **Conflicts**: a role still assigned to users can't be deleted, and the error comes back as a `409` with an `in_use` detail.
- **Read-only resources over a query**: `UserPermissionsController` is an index-only SchemaApi resource whose `resource_scope` joins through roles.
- **The error format outside resources**: `/authorize` parses its query with a plain schema-model schema and reports problems in the same error format.
