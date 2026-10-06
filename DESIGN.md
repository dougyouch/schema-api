# SchemaApi Design

A Rails controller concern where the API contract for a resource (cars, notes, phones, users, ...) is declared inline as a `schema-model` schema. The schema:

- is the allowlist for input: only `input:` attributes are written to the model
- parses and type-checks everything the client sends: `"abc"` for an integer is a `400 invalid_data`, not a silent `nil` or `0`
- is the only thing rendered: records are never serialized directly, so a new column never leaks into a response
- validates input with ActiveModel validations declared in the schema block
- describes nested resources (has-one, has-many, JSON columns) and how each is maintained on write

`mappable` compiles the copying between schema and model in both directions into straight-line Ruby.

## Goals

1. **The API is at the top of the file.** The `schema` block lists every field a client can send and receive, at every level of nesting.
2. **Secure by default.** Attributes are output-only unless marked `input:`. Search can only filter and sort on declared fields. Nested records are always looked up through their parent.
3. **One write path.** Create, update (PUT), patch, upsert and their bulk forms all run the same per-resource pipeline: find or build, parse, validate, assign, save, render.
4. **Requests and responses look the same.** A resource is always wrapped in its root key, `{ "car": {...} }` or `{ "cars": [...] }`, in both directions.
5. **Standard status codes and one error format** for every failure.
6. **Small, named, overridable steps** with the same names in every controller.
7. **Good defaults, not rules.** Every default (status codes, naming, PUT semantics, pagination, touching, error rendering) is an option or a method a developer can change. See [Defaults and How to Change Them](#defaults-and-how-to-change-them).

## Example

```ruby
class CarsController < ApplicationController
  include SchemaApi

  schema do                                   # model Car, root key "car"/"cars", from the controller name
    model_attribute :id
    model_attribute :vin, input: :create      # settable on create only
    model_attribute :make, input: true
    model_attribute :model, input: true
    model_attribute :year, input: true
    model_attribute :created_at
    model_attribute :updated_at, lock: true   # optimistic locking, see below

    has_many :owners, input: true, key: :person_id do
      model_attribute :person_id, input: :create
      model_attribute :since, input: true
    end

    validates :make, :model, presence: true
    validates :year, numericality: { greater_than: 1885 }, allow_nil: true
  end

  search do
    filter :make
    filter :year, op: %i[gte lte]
    sort :year, :created_at, default: '-created_at'
  end

  paginate :cursor, limit: { default: 25, max: 100 }
  upsert_key :vin
  bulk max: 100

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end
```

```ruby
# config/routes.rb
schema_api_resources :cars, bulk: true, upsert: true
```

| Request | Action | Success |
|---|---|---|
| `GET /cars?make=Ford&sort=-year` | `index` | `200 { cars: [...], meta: {...} }` |
| `GET /cars/1` | `show` | `200 { car: {...} }` |
| `POST /cars` | `create` | `201 { car: {...} }` |
| `PUT /cars/1` | `update` | `200 { car: {...} }` |
| `PATCH /cars/1` | `update` (`request.patch?`) | `200 { car: {...} }` |
| `DELETE /cars/1` | `destroy` | `204` |
| `PUT` / `PATCH /cars/upsert` | `upsert` | `201` if created, `200` if updated |
| `POST /cars/bulk_create` | `bulk_create` | `200 { cars: [...], errors: [...], meta: {...} }` |
| `PUT` / `PATCH /cars/bulk_update` | `bulk_update` | same |
| `PUT` / `PATCH /cars/bulk_upsert` | `bulk_upsert` | same |

`schema_api_resources` is `resources` plus the collection routes for the enabled add-ons. Rails sends PUT and PATCH to the same action, so each write action switches on `request.patch?` for partial semantics.

`resource_scope.new` builds through the `where`, so new cars get `tenant` set without overriding `build_resource`.

## Declaring the Schema

### `schema`

The first argument can be nothing, a model class or a schema class:

```ruby
schema do ... end                                    # model and root key from the controller name
schema(AuthDB::User) do ... end                      # explicit model
schema(UserSchema, model: AuthDB::User) do ... end   # shared schema class, extended by the block
schema(AuthDB::User, root: :member, collection_root: :members) do ... end
```

| Setting | Default | Override |
|---|---|---|
| model | controller name, demodulized and singularized: `Admin::CarsController` → `Car` | first argument or `model:` |
| root key | controller name singularized: `CarsController` → `car` | `root:` |
| collection root key | controller name: `cars` | `collection_root:` |
| schema class | `CarsController::CarSchema` | `class_name:` |

The root key comes from the controller rather than the model or table, because the controller is the API: `AuthDB::User` with table `auth_users` behind `UsersController` is `user`/`users`, matching `/users`. When the controller name doesn't fit (e.g. `MeController`), pass `root:`. Root keys are always on and used for requests and responses alike.

Passing a schema class subclasses it, so the block can add attributes and validations for this controller (an admin controller adding `role`) without changing the shared class. A shared schema includes `SchemaApi::ResourceSchema`.

### Attribute options

`SchemaApi::ResourceSchema` adds options on top of `schema-model`'s `attribute`:

| Option | Meaning |
|---|---|
| *(none)* | read-only. Parsed and type-checked when sent, available to hooks, never written to the model. |
| `input: true` | written on create, update and patch, and rendered |
| `input: :create` | written on create only; sending a different value on update is a `400 create_only_attribute` |
| `write_only: true` | written, never rendered, kept when a PUT leaves it out (`password`) |
| `lock: true` | read-only, and used for optimistic locking |
| `model: :email_address` | model attribute when it differs from the API name |
| `model: false` | not copied to or from the model (e.g. `password_confirmation`, used in a hook) |
| `value: ->(record) { ... }` | computed output, compiled to a mappable `custom_map`; `includes:` adds what it needs to eager loading |
| `set: :method` / `on: :create` | filled by the server from a controller method or proc, on create or on every save that changes the record; not input |
| `format: :iso8601` | time output format: `:iso8601`, `:iso8601_usec` (default for `lock:`), `:unix`, or a proc |
| `roles: [:admin]` | *(future)* only those roles can read or write it; `input_roles:`/`output_roles:` to split |

### Read-only fields

Clients usually send back what they got from GET, so read-only fields aren't rejected. They're parsed like every other field (a bad `created_at` is still a `400`) and kept on the input schema, but never assigned to the model. Two of them have meaning on writes:

- **`id`** on `update` must match the URL, or it's a `400 id_mismatch`. In bulk updates and nested has-many items it identifies the record.
- **`lock: true`** fields enable optimistic locking. When the client sends the field, the save locks the row (`SELECT ... FOR UPDATE` inside the write transaction), compares the stored value to the sent one, and returns a `409 stale_resource` if they differ. Not sending it skips the check; `lock: :required` makes it mandatory on update. Times used as locks render with microseconds so the round trip compares exactly. A Rails `lock_version` column works the same way with `model_attribute :lock_version, lock: true`.

Locking the row and saving through the model, rather than `UPDATE ... WHERE updated_at = :old`, keeps model validations and callbacks running; the row lock makes the compare-and-save atomic.

### `model_attribute`

`model_attribute :created_at` looks up the attribute's type on the model and calls `attribute` with the matching schema type and format:

| ActiveRecord type | Schema type | Notes |
|---|---|---|
| `integer`, `bigint` | `:integer` | |
| `string`, `text`, `uuid`, `citext` | `:string` | |
| `boolean` | `:boolean` | |
| `float` | `:float` | |
| `decimal` | `:decimal` | needs a `parse_decimal` (BigDecimal) in schema-model, rendered as a string |
| `datetime`, `timestamp`, `time` | `:time` | `format: :iso8601` |
| `date` | `:date` | |
| `json`, `jsonb` | `:hash` | or a nested schema, see below |
| array column | `:array` with `data_type:` | |
| enum | `:string` | adds `validates inclusion: Model.<enums>.keys` |

Inside a nested block, the model is the association's class (`Car.reflect_on_association(:owners).klass`), so `model_attribute` works at every level.

Types come from `Model.attribute_types`, which needs a database connection, so declarations are recorded and the schema tree is finalized on first use. `SchemaApi.finalize_all!` finalizes every controller, for an initializer in production or a spec that catches a mistyped column in CI. An unknown attribute raises `SchemaApi::UnknownAttributeError` naming the controller and the path (`affiliations.tenant_id`). `model_attribute :x, :string` skips the lookup.

## Nested Resources

Nested resources are declared with `has_one`, `has_many` and `belongs_to`, and can nest to any depth. The difference that matters is ownership:

- **`has_one` and `has_many` are owned.** The children exist for the parent (a user's affiliations, an affiliation's attributes row with a unique `affiliation_id`), so their `input:` attributes write to the child records.
- **`belongs_to` is referenced.** The related record is shared (a manufacturer has thousands of cars), so the client only chooses which one by key. Its attributes are rendered, never written.

```ruby
class UsersController < ApplicationController
  include SchemaApi

  schema(AuthDB::User) do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :email, input: true

    has_many :affiliations, input: true, key: :tenant_id do
      model_attribute :id
      model_attribute :tenant_id, input: :create
      attribute :affiliation_roles, :array, data_type: :string, input: true,
                values_of: { association: :roles, field: :name }
      has_one :affiliation_attributes, input: true do  # table with a unique affiliation_id
        model_attribute :department, input: true
        model_attribute :title, input: true
      end
    end
  end
end
```

```json
{
  "user": {
    "id": 1, "name": "Ada", "email": "ada@example.com",
    "affiliations": [
      {
        "id": 7, "tenant_id": 3,
        "affiliation_roles": ["admin", "billing"],
        "affiliation_attributes": { "department": "Engineering", "title": "Lead" }
      }
    ]
  }
}
```

### What backs a nested schema

When the schema is finalized, each nested schema is matched to the model:

| Model side | Detected by | Stored as |
|---|---|---|
| association (`has_many`, `has_one`) | `reflect_on_association` | child records, each with its own mappings |
| `belongs_to` association | `belongs_to` in the schema | the foreign key only, see below |
| JSON column | `json`/`jsonb` attribute type | the nested schema's `as_json`, validated and typed by the schema |
| collection of values | `values_of:` | child records, one per value (`roles` rows with a `name`), shown as an array of scalars |

`model:` names the association or column when it differs from the API name. Each nested schema class gets its own mapping classes, generated the same way as the root's.

### `belongs_to`: assign by key

```ruby
schema do
  model_attribute :id
  belongs_to :manufacturer, input: true do   # Car belongs_to :manufacturer
    model_attribute :id
    model_attribute :name
  end
end
```

```json
request:  { "car": { "manufacturer_id": 9 } }
response: { "car": { "id": 1, "manufacturer": { "id": 9, "name": "Ford Motor Co" } } }
```

- **Input is the foreign key.** `belongs_to ..., input: true` adds a `manufacturer_id` input attribute, typed from the model column. That's the only way to change the reference.
- **Output is the object.** The foreign key is left out of the response, and the nested `manufacturer` object is rendered in its place.
- **Strictly key-based.** Clients that send back what they got from GET will send `manufacturer: { id: 9, ... }`, often alongside a `manufacturer_id` with a different value. That's fine: the nested object is parsed (bad types are still a `400`) and otherwise ignored, and `manufacturer_id` wins. A nested object sent without `manufacturer_id` changes nothing.
- **The key is checked.** The id is looked up in a scope before it's assigned, so a client can't point a car at another tenant's manufacturer. A missing or out-of-scope id is a `422` on `manufacturer_id` with error `not_found`.
- **The scope is required.** `belongs_to ..., input: true` without `scope:` raises `SchemaApi::MissingScopeError` when the schema is finalized, so every writable reference makes its lookup explicit. `scope: :manufacturer_scope` calls a controller method (e.g. `Manufacturer.where(tenant: current_tenant)`), a lambda runs in the controller, and `scope: :all` opts out deliberately. Output-only `belongs_to` doesn't need one.
- **Not sent means unchanged, on PUT too.** Since GET responses don't include `manufacturer_id`, a client that PUTs back a GET response would otherwise clear every reference. Sending `"manufacturer_id": null` clears it.

| Option | Default | Changes |
|---|---|---|
| `key:` | `:id` | look up by another unique field: `key: :code` accepts `manufacturer_code` |
| `scope:` | required with `input: true` | a controller method name, a lambda run in the controller, or `:all` |
| `render_key:` | `false` | `true` also renders `manufacturer_id` |
| `on_put_missing:` | `:keep` | `:nullify` applies normal PUT semantics |
| `optional:` | from the model's association | whether `null` is allowed |

### Matching items: `key:`

A has-many item is matched to an existing child by its key, `id` by default. `key: :tenant_id` matches affiliations by tenant, so a client can write `{ "tenant_id": 3, ... }` without knowing affiliation ids. Composite keys are `key: %i[tenant_id kind]`. Duplicate keys in one request are a `400 duplicate_key` on the item.

Children are always looked up through the parent (`user.affiliations`), never with a global `find`, so a client can't attach or modify another parent's records by sending their ids. An `id` that isn't one of the parent's children is a `400 invalid_data` with a `not_found` detail on that item.

### Write semantics

PUT replaces and PATCH merges, at every level:

| | PUT (and create) | PATCH |
|---|---|---|
| scalar attribute not sent | set to `nil` (or its schema `default:`) | unchanged |
| scalar sent as `null` | `nil` | `nil` |
| has-one not sent | destroyed | unchanged |
| has-one object | updated in place if it exists (same record), else created; PUT semantics inside | updated in place, or created; PATCH semantics inside |
| has-one `null` | destroyed | destroyed |
| has-many not sent | emptied | unchanged |
| has-many list | the list is the new collection: matched items replaced (PUT), unmatched items created, children not in the list removed | matched items patched, unmatched items created, children not in the list kept, items with `"_destroy": true` removed |
| JSON column | replaced with the nested schema's value | deep-merged with only the fields sent (`as_json(only_set: true)`) |
| `values_of` array | replaced | replaced (arrays are values, as in JSON Merge Patch) |
| `belongs_to` key not sent | unchanged (`on_put_missing: :keep`) | unchanged |
| `belongs_to` key sent | reference changed | reference changed |

PATCH on a has-many only touches the items the client sent. That's the safe default: a client that sends one affiliation can't delete the others by accident, and two clients changing different items don't overwrite each other.

How removed children go away is per association: `on_remove: :destroy` (default), `:delete`, `:nullify`, or `:error` (removing is a `400`, for collections only the server prunes). An association without `input:` is output-only and never touched, whatever is sent.

### Saving a tree

`SchemaApi::TreePlanner` plans the changes above without writing anything, then `SchemaApi::TreeExecutor` applies them in one transaction:

1. Assign the root's scalar input attributes and save it (children may need its id).
2. For each nested association, load the existing children once, match items by key, and for each item: assign, save, recurse.
3. Remove unmatched children per `on_remove:`.
4. If any record in the tree was created, changed or removed and the root wasn't saved with changes of its own, touch the root (see below).

The writer saves each record explicitly rather than relying on `accepts_nested_attributes_for` or autosave, so models need no extra configuration, matching works on any key, and a failure is reported at its exact path. Any failure rolls back the whole resource: a single resource is all or nothing. (Best effort applies across the items of a bulk request, not within one resource.)

Errors use the request's paths: `affiliations[0].affiliation_attributes.department`. Model errors from saving a child are reported under that child's path.

### Touching the root

Any change anywhere in the tree bumps the root. Changing `affiliations[0].affiliation_attributes.department` updates the user's `updated_at`, so:

- the root's optimistic lock covers the whole tree: a client holding an old copy of the user gets a `409`, whichever nested record changed
- "which users changed since T" is `where('updated_at > ?', t)`, without checking every child table

Only real changes count. `TreeExecutor` tracks whether any record in the tree was created, removed or saved with changed attributes, and calls `touch_resource(record, changes)` once per write, after the saves and inside the transaction, only when something changed. A PUT that sends exactly what's stored saves nothing and bumps nothing. The default `touch_resource` calls `record.touch` when the root wasn't already saved with changes of its own (which bumped `updated_at` already). Override it, or use `touch:`, for other versioning schemes:

```ruby
schema(touch: true)                     # default: record.touch when only children changed
schema(touch: false)                    # don't touch
schema(touch: :bump_version_number)     # call a model or controller method instead

def touch_resource(record, changes)     # or take full control; only called when changes.any?
  record.bump_version_number!
  AuditLog.record(record, changes.paths)
end
```

`changes` lists the paths that were created, updated and removed (`affiliations[0].affiliation_attributes`), so hooks can tell what moved.

### Validation

Every nested schema runs its own validations; input associations get `validates ..., schema: true` automatically so a child's errors surface on the parent with their paths. For PATCH, validation runs against the result rather than the patch: the current record tree is mapped into a schema, the patch is overlaid by key, and the merged tree is validated. So `presence: true` on a field the client didn't send passes when the record has a value.

### Reading a tree

The output mappings render children recursively, and the schema tree also produces the eager-loading tree, so `show`, `update` and `index` load with `includes(affiliations: :roles)` automatically. The includes are applied on top of `resource_scope` (by `scoped_resources`), so overriding `resource_scope` keeps them. `includes: false` on an association turns one off.

## The Write Pipeline

Every write action runs the same per-resource method:

```ruby
def create
  @resource = build_resource
  write_resource!(@resource, resource_input)
  render_resource(@resource, status: :created)
end

def update
  write_resource!(resource, resource_input, partial: request.patch?)
  render_resource(resource)
end

def write_resource!(record, input, partial: false)
  context = WriteContext.new(action: action_name, record:, input:, partial:)
  check_input!(context)                                         # 1. parsing errors, id, create-only
  run_callbacks(:validation) { validate_input!(context) }       # 2. schema + controller validations
  transaction do
    check_lock!(context)                                        # 3. optimistic lock
    run_callbacks(:assign) { assign_resource(context) }         # 4. plan the tree
    run_callbacks(:save) { save_resource!(context) }            # 5. assign and save the tree
    touch_resource(record, context.changes) if context.changes.any? # 6. bump the root
  end
  record.reload
  run_callbacks(:commit) { }                                    # 7. after the transaction commits
  record
end
```

1. **Parse** (`resource_input`). Reads `request.raw_post` (not `params`, which Rails pads with `controller`, `action` and wrapped keys), takes the value under the root key, and builds the schema with `from_hash`. Malformed JSON or a missing root key is a `400 malformed_request`. Parsing errors (bad types, unknown attributes) are a `400 invalid_data`.
2. **Validate** (`validate_input!`). Schema validations at every level; a `422 validation_error` on failure.
3. **Lock** (`check_lock!`). Locks the row and compares `lock:` fields; `409 stale_resource` on a mismatch. It runs before anything is assigned, because locking the row reloads the record.
4. **Plan** (`assign_resource`). `TreePlanner` matches nested items, decides creates, updates and removals, and looks up belongs_to keys, without writing anything. Every problem it finds is raised together.
5. **Save** (`save_resource!`). `TreeExecutor` assigns each record with the compiled mappings and saves the root and nested records, parent first. `ActiveRecord::RecordInvalid` becomes a `422 validation_error` with the model's errors at their paths; `ActiveRecord::RecordNotUnique` becomes a `409 conflict`.
6. **Touch** (`touch_resource`). Bumps the root when anything in the tree changed; see [Touching the root](#touching-the-root).
7. **Commit.** `after_commit` callbacks run once the transaction has committed, for work that must not happen on rollback (enqueueing jobs, webhooks).

Every step is a method to override, and each one receives the `WriteContext`: the action, the record, the input schema, `partial`, and after assignment, the tree's `changes`.

### Callbacks and controller validations

Callbacks hook into the steps without overriding them. Each takes a method name or a block, `only:`/`except:` on action names, and `if:`/`unless:`:

| Callback | Runs | Typical use |
|---|---|---|
| `before_validation`, `after_validation`, `around_validation` | around step 2 | normalize input, set defaults from the current user |
| `validate_input :method` | during step 2 | rules that need the controller, e.g. "tenant 3 is one this user may join" |
| `before_assign`, `after_assign`, `around_assign` | around step 3 | set `updated_by`, hash `password` |
| `before_save`, `after_save`, `around_save` | around step 5, inside the transaction | `bump_version_number`, audit rows |
| `after_commit` | after the transaction | enqueue jobs, send webhooks |

```ruby
validate_input :check_tenants
before_save :bump_version_number, only: %i[update upsert bulk_update bulk_upsert]
after_commit { |context| UserChangedJob.perform_later(context.record.id) if context.changes.any? }

private

def check_tenants(context)
  context.input.affiliations.each_with_index do |affiliation, i|
    next if current_account.tenant_ids.include?(affiliation.tenant_id)

    context.errors.add("affiliations[#{i}].tenant_id", :not_allowed, message: 'is not a tenant you belong to')
  end
end
```

Schema validations (`validates` in the schema block) can only see the data. `validate_input` exists for rules that need the request, the current user or the database; its errors join the schema's in the same `422`.

Callbacks run per resource, so they apply to every item in a bulk request. Use `before_action` for authorization and lookups that happen once per request.

## Upsert

```ruby
upsert_key :vin           # resource_scope.find_by(vin: input.vin)
upsert_key :remote_id     # resource_scope supplies tenant_id: unique(tenant_id, remote_id)
upsert_key %i[source remote_id]
```

`upsert` finds the record by its key within `resource_scope`, then runs `write_resource!` as an update if found or a create if not. PUT replaces and PATCH merges on the update path; on the create path both are creates. Responses are `201` for a create and `200` for an update.

Key fields must be schema attributes and present in the input (`400 missing_upsert_key` otherwise). Scope columns such as `tenant_id` come from `resource_scope`, so they're part of the effective unique key without being sent. When a lookup is more than `find_by`, override it:

```ruby
def find_resource_for_upsert(input)
  resource_scope.find_by('lower(email) = ?', input.email.downcase)
end

# bulk_upsert: one query for the batch; returns { key => record }
def find_resources_for_upsert(inputs)
  resource_scope.where(remote_id: inputs.map(&:remote_id)).index_by(&:remote_id)
end
```

Two requests upserting the same new key can both decide to create. With a unique index (required for a meaningful upsert key), the second insert raises `RecordNotUnique`, and upsert retries once as an update.

## Bulk Actions

`bulk_create`, `bulk_update` and `bulk_upsert` take the collection root, `{ "cars": [ {...}, {...} ] }`, and process items best effort: each item runs `write_resource!` in its own transaction, the ones that succeed are saved, and the ones that fail are reported.

```json
{
  "cars": [ { "id": 1, "vin": "..." }, null, { "id": 3, "vin": "..." } ],
  "errors": [
    { "index": 1, "error": { "code": "validation_error", "message": "Car is invalid",
                             "details": [ { "field": "make", "error": "blank", "message": "Make can't be blank" } ] } }
  ],
  "meta": { "created": 2, "updated": 0, "failed": 1 }
}
```

- `cars[i]` is the result for input item `i`, `null` when it failed, so clients line results up by position. Error paths are relative to the item.
- The response is `200` whenever the request itself was processed, even if every item failed; clients check `errors`. A body that isn't a list under the root key, or has more than `bulk max:` items, is a `400` and nothing is processed.
- To change the status, pass `bulk status:` a symbol or a lambda, or override `bulk_response_status(result)`:

  ```ruby
  bulk status: ->(result) { result.all_failed? ? :unprocessable_entity : :ok }
  bulk status: ->(result) { result.any_failed? ? :multi_status : :ok }
  ```
- `bulk_update` items are matched by `id` (`bulk key: :vin` to change it). Records are loaded in one query; a missing id is a `404 not_found` on that item.
- `bulk_upsert` loads existing records with one `find_resources_for_upsert` call.
- `bulk atomic: true` switches a controller to all-or-nothing: one transaction, and any failure rolls back the batch and returns the errors with `422`.

Items are saved one at a time so model validations and callbacks run. An `insert_all`/`upsert_all` fast path that skips them is a possible later opt-in.

## Mappings

When the schema is finalized, `SchemaApi::MappingBuilder` generates `Mappable::Mapping` classes for each schema class in the tree:

```ruby
# model -> schema, for rendering: output attributes; nested output uses the child's mapping
class CarsController::CarSchema::OutputMapping
  include Mappable::Mapping
  map :id
  map :make
  custom_map(:owners) { |car| car.owners.map { |owner| OWNER_OUTPUT.map(owner, OwnerSchema.new) } }
end

# schema -> model, for create and PUT: scalar input attributes
class CarsController::CarSchema::InputMapping
  include Mappable::Mapping
  map :vin, if: :creating
  map :make
  attr_accessor :creating
end

# schema -> model, for PATCH: only what was sent
class CarsController::CarSchema::PatchMapping
  include Mappable::Mapping
  map :make, if_src: :make_was_set?
end
```

The input mappings copy scalars; `TreeExecutor` handles associations and uses each child's mappings for its scalars. Mappable ANDs conditions, so "sent" and "allowed" are separate classes, each straight-line code. Roles later become an `if:` on the mapping instance.

## Rendering

```ruby
def render_resource(record = resource, status: :ok)
  render json: { root_key => resource_json(record) }, status: status
end
```

`resource_json` maps the record into a schema with `OutputMapping` and calls `as_json(include_nils: true)` with an output filter. Including nils keeps every response the same shape; the filter drops `write_only` attributes (and later, attributes the viewer's roles can't read).

## Overridable Methods

The same names in every controller, all private. A reader named after the resource (`car`, `user`) is an alias for `resource`.

| Method | Default |
|---|---|
| `resource_scope` | `Model.all` |
| `scoped_resources` | `resource_scope` with the schema's `includes` |
| `find_resource` | `scoped_resources.find(params[:id])` |
| `resource` | `@resource ||= find_resource` |
| `build_resource` | `resource_scope.new` |
| `resource_input` | parse the body under the root key (memoized) |
| `resource_inputs` | parse the body under the collection root (bulk) |
| `validate_input!(context)` | schema validations, then `validate_input` methods |
| `assign_resource(context)` | the TreePlanner plan |
| `save_resource!(context)` | TreeExecutor: assign with the mappings and save the tree |
| `check_lock!(context)` | row lock and `lock:` comparison |
| `touch_resource(record, changes)` | `record.touch` when only children changed |
| `bulk_response_status(result)` | `bulk status:`, default `:ok` |
| `destroy_resource!(record)` | `record.destroy!` |
| `find_resource_for_upsert(input)` | `scoped_resources.find_by(upsert key)` |
| `find_resources_for_upsert(inputs)` | one `where` on the upsert key |
| `resource_json(record)` | see Rendering |
| `render_resource(record, status:)` | `{ root_key => ... }` |
| `search_resources` | `resource_scope` with the search applied |
| `render_resources(records, meta)` | `{ collection_root_key => [...], meta: }` |
| `schema_roles` | *(future)* `[]`; the viewer's roles |

`schema(..., actions: %i[index show])` limits which actions are defined, on top of what the routes allow. Actions are ordinary methods, so a controller can also define its own `create` and still call `write_resource!` and `render_resource`.

## Errors

Every error response has one shape, built by `SchemaApi::ErrorSchema`:

```json
{
  "error": {
    "code": "validation_error",
    "message": "User is invalid",
    "details": [
      { "field": "email", "error": "invalid", "message": "Email is invalid" },
      { "field": "affiliations[0].affiliation_attributes.department", "error": "blank", "message": "Department can't be blank" }
    ]
  }
}
```

`details[].error` is a machine code: a schema-model parsing code (`invalid`, `incompatible`, `unknown_attribute`), one of SchemaApi's (`create_only_attribute`, `id_mismatch`, `duplicate_key`, `missing_upsert_key`, `not_found`), or the ActiveModel error type (`blank`, `taken`, `too_long`).

| Status | `code` | Raised for |
|---|---|---|
| 400 | `malformed_request` | body isn't JSON, or the root key is missing |
| 400 | `invalid_data` | parsing errors in the body or search params; validation details are included too, so the client sees everything at once |
| 403 | `forbidden` | *(future)* writing an attribute the viewer's roles can't |
| 404 | `not_found` | `ActiveRecord::RecordNotFound` |
| 409 | `conflict` | `ActiveRecord::RecordNotUnique` |
| 409 | `stale_resource` | optimistic lock mismatch |
| 422 | `validation_error` | schema validations or `ActiveRecord::RecordInvalid` |

Each is a `SchemaApi::Error` subclass with a `code` and `status`, handled by one `rescue_from` that calls `render_error(error)`. Bulk actions catch the same errors per item and put them in `errors`. Apps can raise them or subclass them, and override `render_error` to log or add a request id.

## Index: Search, Sort and Pagination

`index` is a search endpoint, not "list everything". Every request has a limit, and only declared filters and sorts are accepted.

```ruby
search do
  filter :make                              # ?make=Ford          -> eq (default op)
  filter :model, op: :contains              # ?model=bron         -> ILIKE '%bron%'
  filter :status, op: :in                   # ?status=active,sold
  filter :year, op: %i[gte lte]             # ?year[gte]=2010
  filter :'owners.person_id'                # ?owners.person_id=5 -> joins owners
  filter(:q, :string) { |scope, q| scope.where('make ILIKE :q OR model ILIKE :q', q: "%#{q}%") }

  sort :year, :created_at, default: '-created_at'  # ?sort=-year,created_at
end
```

- **The search params are a schema too.** `search` builds a `CarsController::CarSearchSchema`, so `?year[gte]=new` or `?limit=abc` is a `400 invalid_data` in the standard format, and unknown params are rejected.
- **Filter types come from the resource schema**, including nested attributes one level down (`owners.person_id`), which filter through a subquery on the association so rows aren't duplicated. A filter that isn't a schema attribute names its type and takes a block.
- **Operators** (`eq`, `not_eq`, `in`, `contains`, `starts_with`, `gt`, `gte`, `lt`, `lte`, `null`) compile to Arel, so values are always bound parameters.
- **Sort** takes declared fields only, `-` for descending, with the primary key appended so the order is stable.

### Pagination

Which pagination fits depends on the table, so each controller picks:

```ruby
paginate :cursor, limit: { default: 25, max: 100 }                 # default
paginate :offset, limit: { default: 50, max: 200 }, count: true    # ?page=3, meta.total_count always
paginate :offset, count: :optional                                 # meta.total_count only with ?count=true
paginate %i[cursor offset], count: :optional                       # client chooses: ?cursor= or ?page=
```

| Mode | Params | `meta` | Good for |
|---|---|---|---|
| `:cursor` | `?limit=`, `?cursor=` | `limit`, `next_cursor` | large tables and feeds; stays fast and doesn't skip or repeat rows when records change between pages |
| `:offset` | `?limit=`, `?page=` | `limit`, `page`, and `total_pages` with a count | small tables and admin UIs with page numbers |

The cursor is an opaque token for keyset pagination on the sort fields plus the id. `count:` (`true`, `:optional`, or `false`, the default) adds `meta.total_count`; it's a separate `COUNT(*)` on the filtered scope, which is why it's opt-in. A `limit` over `max` is a `400`, not silently capped.

`POST /cars/search` (`schema_api_resources :cars, search: true`) accepts the same search schema as a JSON body under the `search` key, for queries too long or structured for a query string.

## Roles (future)

```ruby
model_attribute :role, input: true, roles: [:admin]
model_attribute :salary, output_roles: %i[admin hr]

def schema_roles
  current_account.roles
end
```

Output leaves out attributes the viewer's roles can't read. Input that writes one is a `403 forbidden` naming the field, so clients find out rather than having it silently dropped. Filters and sorts on restricted attributes get the same check, and roles work at every nesting level.

## GraphQL

`SchemaApi::Graphql` serves a controller's schema over GraphQL. It's optional: an app adds the `graphql` gem and `require 'schema_api/graphql'`.

```ruby
class GraphqlController < ApplicationController
  include SchemaApi::Graphql
  graphql_resources UsersController, OrganizationsController, max_depth: 15
end

post 'graphql', to: 'graphql#execute'
```

### Why graphql-ruby

graphql-ruby handles the GraphQL language: parsing, the spec's validation rules, variables, fragments, directives, introspection (for GraphiQL and codegen), and depth limits. Building that in-house would add bugs without making the API any better. What's specific to SchemaApi (types from schemas, resolving through controllers) is in-house, and apps never write graphql-ruby type classes. Gems that build types from ActiveRecord columns were left out because they expose whatever the table has.

### Types

- Each controller's schema class becomes an object type named after its root (`User`). Nested schemas are named by path (`UserAffiliation`, `UserAffiliationOrganization`).
- Fields are the rendered fields, so write-only fields and unrendered belongs_to keys aren't in the schema at all. Asking for one is a validation error.
- Names stay snake_case, the same as the REST JSON and search params.
- Values are typed the way the Serializer renders them: decimals, dates and times are `String`, `format: :unix` times are `Int`, and hashes and untyped arrays are `JSON`.

### Query fields

| Action | Field | Returns |
|---|---|---|
| `index` | `users(filter:, sort:, limit:, cursor:, page:, count:)` | `UserList { nodes: [User!]!, meta: PageMeta! }` |
| `show` | `user(id: ID!)` | `User` |

Each field is only there when the controller has that action. Pagination arguments come from `paginate`, so `cursor` only exists for cursor pagination. `PageMeta` matches REST's `meta`.

`filter` is generated from `search`. Each filter is an input object with one field per operator, and dots in nested names become underscores:

```graphql
cars(filter: { year: { gte: 2010 }, status: { in: ["active"] }, owners_person_id: { eq: 5 } })
```

The argument is turned back into the search params REST takes, `{ "year" => { "gte" => 2010 }, ... }`, so `Search::ParamsParser` checks it. Limits, sorts and cursors are validated exactly as on `index`.

### Resolving through the controller

`Graphql::ControllerRunner` runs each field the way Rails runs the REST action:

1. Build the controller for the request, with `action_name` (`index` or `show`) and `params` (`id`).
2. Run its `process_action` callbacks. `before_action` with `only:`/`except:` applies per field, and `around_action` wraps the work.
3. Inside the callbacks: `search_page` (the same as `index` without the rendering) or `resource`, then `resource_json` for each record.

The output is therefore the REST output, including any `resource_scope`, `find_resource` or `resource_json` override. Each root field gets its own controller instance, so memoized lookups don't leak between fields.

### Errors

The response follows GraphQL conventions:

- **Status:** a request that ran is a `200`, even when a field failed.
- **Failed fields:** a `SchemaApi::Error` makes its field `null`, and its siblings still resolve. The error goes in `errors`, and `extensions` carries SchemaApi's `code`, `status` and `details`.
- **Not found:** `ActiveRecord::RecordNotFound` becomes `not_found` ("User not found"), as `rescue_from` does in REST.
- **Halted callbacks:** a `before_action` that renders instead of raising stops the field with a `forbidden` naming the status it set.
- **Bad request bodies:** a body that isn't a GraphQL request (bad JSON, no `query`) is a REST-style `400 malformed_request`.

### Not yet

- Mutations. Create and update input types would come from `input?(creating)`, and every mutation would go through `write_resource!`. GraphQL already tells an omitted argument apart from `null`, which is what PATCH needs.
- Nested-route controllers (`parent`). `graphql_resources` raises for them for now.
- Using lookahead (the fields a query selected) to skip eager loading and computed fields nobody asked for.
- `Int` is 32-bit in GraphQL, so integer ids over 2^31 need a wider type.

## Library Layout

One class per file. The entry point autoloads everything else.

```
lib/schema_api.rb                       # the concern: included hook, rescue_from, finalize_all!
lib/schema_api/class_methods.rb         # schema, search, paginate, upsert_key, bulk, callback macros
lib/schema_api/definition.rb            # a controller's settings; finalize!
lib/schema_api/naming.rb                # model, root and collection root from controller/model/options
lib/schema_api/schema_class_builder.rb  # the schema class constant on the controller
lib/schema_api/resource_schema.rb       # mixed into schema classes; resource_schema/class_methods.rb has
                                        #   model_attribute, belongs_to, api_fields
lib/schema_api/field.rb                 # reads SchemaApi's options off a schema field
lib/schema_api/type_resolver.rb         # ActiveRecord type -> schema type
lib/schema_api/schema_finalizer.rb      # types, nested backing, scope and key checks, mappings
lib/schema_api/mapping_builder.rb       # output/input/patch mappable classes per schema class
lib/schema_api/includes_builder.rb      # eager-loading tree
lib/schema_api/lookup.rb                # resource_scope, find/build, input parsing, belongs_to and upsert lookups
lib/schema_api/persistence.rb           # the write pipeline
lib/schema_api/rendering.rb             # render_resource(s), render_error
lib/schema_api/input_parser.rb          # raw body -> data under the root key
lib/schema_api/input_checker.rb         # parsing errors, id mismatch, create-only, required lock
lib/schema_api/create_only_check.rb
lib/schema_api/patch_merger.rb          # current tree + patch -> merged schema for validation
lib/schema_api/error_collector.rb       # parsing/validation errors with request paths
lib/schema_api/model_errors.rb          # ActiveRecord errors named by API field
lib/schema_api/tree_planner.rb          # nested matching, removals, references, JSON values
lib/schema_api/tree_node.rb             # the plan
lib/schema_api/child_matcher.rb         # has_many items -> existing children by key
lib/schema_api/tree_executor.rb         # assigns and saves the plan
lib/schema_api/tree_changes.rb          # created/updated/removed paths
lib/schema_api/write_context.rb         # action, record, input, partial, changes, errors
lib/schema_api/callback_chain.rb        # before/after/around callbacks and validate_input
lib/schema_api/presenter.rb             # record -> schema tree
lib/schema_api/serializer.rb            # schema tree -> response hash
lib/schema_api/actions/                 # crud, search, upsert, bulk
lib/schema_api/bulk_config.rb, bulk_result.rb
lib/schema_api/search/                  # definition, filter, sort, params_parser, query
lib/schema_api/pagination/              # config, cursor, offset, page
lib/schema_api/error_schema.rb, error_list.rb, errors.rb
lib/schema_api/routing.rb               # schema_api_resources
lib/schema_api/graphql.rb               # optional GraphQL endpoint concern; graphql/ has the
                                        #   schema, type and filter builders and ControllerRunner
```

Dependencies: `schema-model` (0.12+, for the `:decimal` type, the `:datetime` alias, association `_was_set?` and parsing error codes), `model-mapper` (mappable), `actionpack`, `activerecord`.

## Build Order

Steps 1 to 6 and GraphQL queries are built and tested. Roles and GraphQL mutations are next.

1. Naming, `ResourceSchema` (flat attributes, `model_attribute`, finalize), mappings, rendering, `show`.
2. Input parsing, the write pipeline, errors: `create`, `update` (PUT and PATCH), `destroy`.
3. Optimistic locking.
4. Nested resources: `TreePlanner`/`TreeExecutor`, `PatchMerger`, nested errors and eager loading.
5. Search and both pagination modes.
6. Upsert, then bulk actions.
7. Roles.
8. GraphQL: queries (built), then mutations.

## Defaults and How to Change Them

| Default | Change it with |
|---|---|
| model, root keys and schema class from the controller name | `schema(Model, root:, collection_root:, class_name:)` |
| attributes are read-only | `input: true`, `input: :create`, `write_only: true` |
| read-only fields in a request are parsed and ignored | override `check_input!` to reject them |
| PUT sets unsent input attributes to `nil` | attribute `default:`; override `assign_resource` |
| `belongs_to` key: input as `<name>_id`, not rendered, unchanged when not sent | `key:`, `render_key: true`, `on_put_missing: :nullify` |
| writable `belongs_to` must declare `scope:` | `scope: :all` to opt out |
| PATCH on has-many touches only the items sent | `patch: :replace` on the association |
| removed has-many children are destroyed | `on_remove: :delete`, `:nullify`, `:error` |
| root is touched when anything in the tree actually changed | `schema(touch: false)`, `touch: :method`, override `touch_resource` |
| optimistic lock checked when the lock field is sent | `lock: :required`, or no `lock:` |
| eager loading from the schema tree | `includes: false` on an association; override `resource_scope` |
| cursor pagination, no counts | `paginate :offset`, `paginate %i[cursor offset]`, `count:` |
| bulk is best effort, status `200` | `bulk atomic: true`, `bulk status:`, override `bulk_response_status` |
| status codes: `201` create, `204` destroy, `200` otherwise | `status:` on `render_resource`; define the action yourself |
| error format | subclass `SchemaApi::Error`; override `render_error` |
| all CRUD actions defined | `schema(actions: [...])` |

## Decisions

Settled during design review (2026-10-05):

- Module name `SchemaApi`.
- Read-only fields in a request are parsed and kept on the input schema, not rejected; `lock:` fields drive optimistic locking.
- PUT sets unsent input attributes to `nil`.
- Root keys are always on; requests and responses have the same shape.
- Pagination mode and counts are chosen per controller; cursor is the default.
- Bulk actions are best effort by default, with status `200` that can be changed.
- `has_one`/`has_many` are owned and written; `belongs_to` is assigned by key only (`<name>_id`), strictly: the nested object in a request never changes the reference.
- A writable `belongs_to` must declare `scope:`; finalize raises otherwise.
- PATCH on a has-many only changes the items sent.
- Optimistic locking is on the root only; any real change in the tree touches the root, and a write with no real change touches nothing.
- Hooks exist for validation, assign, save, touch and commit; defaults are conventions developers can change.
- Write-only fields stay unchanged when a PUT leaves them out (2026-10-06, from the auth example).

## Controller Helpers

Added after building the examples, to keep controllers to the API and the rules that are specific to it:

- `model_attributes :a, :b, **options` and `timestamps(lock: true)`.
- **Write-only fields stay unchanged when PUT leaves them out**, like `belongs_to` keys, so secrets aren't cleared by a PUT that doesn't mention them.
- `set:` / `on:` on an attribute (or a `belongs_to`, for its key) for values the server owns: creator, updater, owning application.
- `soft_delete(column = :deleted_at)`: `scoped_resources` hides rows with the column set, and `destroy_resource!` sets it with `touch`.
- `parent :organization, scope:, param:, association:`: the parent is found from the route within its scope (`404` otherwise), `resource_scope` is its has_many, and a private reader returns it.
- `includes:` on computed fields.
- `include SchemaApi` once in a base controller: actions are added by `schema`, and errors raised anywhere in a subclass render in the standard format.
- `SchemaApi.parse!(schema_class, data)` for endpoints that aren't resources.

## Open Questions

Found while building `examples/auth` and `examples/roles`:

1. **Authorizing by what changed.** "Users may not change their affiliations" is best judged from `context.changes` after the save (raising rolls the write back), so a client can still PUT back its own GET response. Is an `after_save` hook enough, or should the gem offer a declared form, e.g. `input: true, unless: :application?` per field or association?
