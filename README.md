# SchemaApi

Rails controllers whose API is a typed schema declared at the top of the file.

The schema is the allowlist for input, parses and type-checks every request, runs your validations, and is the only thing rendered. Records are never serialized directly, so a new column never leaks into a response. Standard create, update, patch, upsert, bulk and search actions, nested resources, optimistic locking and one error format come with it.

Built on [schema-model](https://github.com/dougyouch/schema) for parsing and validation and [model-mapper](https://github.com/dougyouch/mappable) for copying between schemas and models. [DESIGN.md](DESIGN.md) covers the reasoning behind each behavior.

## Installation

Requires Ruby 3.3+ and Rails 7.1+.

```ruby
gem 'schema-api'
```

## Quick Start

```ruby
class CarsController < ApplicationController
  include SchemaApi

  schema do                                    # model Car, root keys "car"/"cars"
    model_attribute :id
    model_attribute :vin, input: :create       # settable on create only
    model_attribute :make, input: true
    model_attribute :model, input: true
    model_attribute :year, input: true
    model_attribute :created_at
    model_attribute :updated_at, lock: true    # optimistic locking

    belongs_to :manufacturer, input: true, scope: :manufacturer_scope do
      model_attribute :id
      model_attribute :name
    end

    has_many :owners, input: true, key: :person_id do
      model_attribute :person_id, input: :create
      model_attribute :since, input: true
    end

    validates :make, presence: true
  end

  search do
    filter :make
    filter :year, op: %i[gte lte]
    sort :year, :created_at, default: '-created_at'
  end

  upsert_key :vin
  bulk max: 100

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end

  def manufacturer_scope
    Manufacturer.where(tenant: current_tenant)
  end
end
```

```ruby
# config/routes.rb
schema_api_resources :cars, bulk: true, upsert: true
```

| Request | Success |
|---|---|
| `GET /cars?make=Ford&year[gte]=2010&sort=-year` | `200 { cars: [...], meta: { limit:, next_cursor: } }` |
| `GET /cars/1` | `200 { car: {...} }` |
| `POST /cars` | `201 { car: {...} }` |
| `PUT /cars/1` | `200`; replaces: input fields not sent become `nil` |
| `PATCH /cars/1` | `200`; changes only what was sent, `null` included |
| `DELETE /cars/1` | `204` |
| `PUT` / `PATCH /cars/upsert` | `201` created, `200` updated |
| `POST /cars/bulk_create`, `PUT`/`PATCH /cars/bulk_update`, `/cars/bulk_upsert` | `200 { cars: [...], errors: [...], meta: {...} }` |

Requests and responses have the same shape: `{ "car": { ... } }`.

## Attributes

| Option | Meaning |
|---|---|
| *(none)* | read-only: rendered; parsed and type-checked if sent, but never written |
| `input: true` | written on create, PUT and PATCH |
| `input: :create` | written on create; on update it must match the stored value |
| `write_only: true` | written, never rendered (`password`) |
| `lock: true` / `lock: :required` | optimistic lock field; a stale value is a `409` |
| `model: :email_address` / `model: false` | model attribute name, or not mapped at all |
| `value: ->(record) { ... }` | computed output |
| `format: :iso8601` | times: `:iso8601`, `:iso8601_usec`, `:unix`, or a proc |

`model_attribute :name` types the attribute from the model's column (integer, string, decimal, boolean, time, date, json, enum with an inclusion validation). It's resolved on first use; call `SchemaApi.finalize_all!` in an initializer or a spec to catch mistyped columns early.

`schema` takes a model or a shared schema class, and the root keys can be overridden:

```ruby
schema(AuthDB::User) do ... end
schema(UserSchema, model: AuthDB::User, root: :member) do ... end   # subclasses UserSchema
```

## Nested Resources

- **`has_one` / `has_many`** are owned: their `input:` attributes write to the child records. They can be backed by an association or a JSON column.
- **`belongs_to`** is referenced: the client sends `manufacturer_id` (or `manufacturer_<key>` with `key:`), and the response renders the `manufacturer` object instead. A writable `belongs_to` must declare `scope:`.
- Has-many items are matched to existing children by `key:` (default `id`), always through the parent.

| | PUT / create | PATCH |
|---|---|---|
| has-many list | becomes the whole collection | matched items patched, new ones created, others kept, `"_destroy": true` removes |
| has-one object | updated in place or created; `null` removes | same, with PATCH semantics inside |
| JSON column | replaced | deep-merged |
| `belongs_to` key not sent | unchanged | unchanged |

Options: `on_remove: :destroy | :delete | :nullify | :error`, `patch: :replace`, `includes: false`, `values_of: { association:, field: }` for a list of values stored as child rows.

A write to any nested record bumps the root (`record.touch`), so the root's lock covers the whole tree. Use `schema(touch: false)`, `touch: :bump_version_number!`, or override `touch_resource(record, changes)`.

## Hooks

```ruby
validate_input :check_tenants                  # rules that need the controller; add to context.errors
before_validation, after_validation, around_validation
before_assign, after_assign, around_assign
before_save, after_save, around_save           # inside the transaction
after_commit { |context| Job.perform_later(context.record.id) }
```

Each takes method names or a block, plus `only:`, `except:`, `if:` and `unless:`. They're given the `WriteContext` (action, record, input, `partial?`, `creating?`, `changes`, `errors`).

Every step is a private method you can override: `resource_scope`, `build_resource`, `find_resource`, `validate_input!`, `assign_resource`, `save_resource!`, `touch_resource`, `render_resource`, `render_error`, `find_resource_for_upsert`, `bulk_response_status`, and more. See DESIGN.md, "Overridable Methods".

## Search and Pagination

`index` always has a limit and only accepts declared filters and sorts. Search parameters are parsed by a schema too, so bad values and unknown parameters are a `400`.

```ruby
search do
  filter :make                                   # ?make=Ford
  filter :model, op: :contains                   # ?model=bron
  filter :year, op: %i[gte lte]                  # ?year[gte]=2010
  filter :status, op: :in                        # ?status=active,sold
  filter :'owners.person_id'                     # ?owners.person_id=5
  filter(:q, :string) { |scope, q| scope.where('make ILIKE ?', "%#{q}%") }
  sort :year, :created_at, default: '-created_at'  # ?sort=-year,created_at
end

paginate :cursor, limit: { default: 25, max: 100 }           # default
paginate :offset, count: true                                # ?page=, meta.total_count
paginate %i[cursor offset], count: :optional                 # client picks; ?count=true
```

`schema_api_resources :cars, search: true` adds `POST /cars/search`, which takes the same parameters as a JSON body under `search`.

## Errors

Every error has one shape:

```json
{ "error": { "code": "validation_error", "message": "Car is invalid",
             "details": [{ "field": "owners[1].person_id", "error": "blank", "message": "Person can't be blank" }] } }
```

| Status | Code |
|---|---|
| 400 | `malformed_request`, `invalid_data` |
| 404 | `not_found` |
| 409 | `conflict`, `stale_resource` |
| 422 | `validation_error` |

Bulk actions are best effort: each item gets its own transaction, and failures are listed by index in `errors`. `bulk atomic: true` makes it all-or-nothing, and `bulk status:` changes the status code.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
