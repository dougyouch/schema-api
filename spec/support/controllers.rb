# frozen_string_literal: true

class ApplicationController < ActionController::API
  private

  def current_tenant
    @current_tenant ||= Tenant.find(request.headers['X-Tenant-Id'])
  end
end

class CarsController < ApplicationController
  include SchemaApi

  schema do
    model_attribute :id
    model_attribute :vin, input: :create
    model_attribute :make, input: true
    model_attribute :model, input: true
    model_attribute :year, input: true
    model_attribute :price, input: true
    model_attribute :status, input: true
    attribute :label, :string, value: ->(car) { [car.year, car.make, car.model].compact.join(' ') }

    belongs_to :manufacturer, input: true, scope: :manufacturer_scope do
      model_attribute :id
      model_attribute :name
    end

    has_many :owners, input: true, key: :person_id do
      model_attribute :id
      model_attribute :person_id, input: :create
      model_attribute :since, input: true
    end

    has_one :options, input: true do
      attribute :color, :string
      attribute :sunroof, :boolean
    end

    model_attribute :created_at
    model_attribute :updated_at, lock: true

    validates :make, presence: true
  end

  search do
    filter :make
    filter :model, op: :contains
    filter :year, op: %i[gte lte]
    filter :status, op: :in
    filter :'owners.person_id'
    filter(:q, :string) { |scope, q| scope.where('make LIKE :q OR model LIKE :q', q: "%#{q}%") }
    sort :year, :make, :created_at
  end

  paginate %i[cursor offset], limit: { default: 2, max: 5 }, count: :optional
  upsert_key :vin
  bulk max: 3

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end

  def manufacturer_scope
    Manufacturer.where(tenant_id: current_tenant.id)
  end
end

class UsersController < ApplicationController
  include SchemaApi

  cattr_accessor :events, default: []

  schema(AuthDB::User, touch: :bump_version_number!) do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :email, input: true
    attribute :password, :string, write_only: true, model: false
    model_attribute :version_number
    model_attribute :updated_at, lock: :required

    has_many :affiliations, input: true, key: :tenant_id do
      model_attribute :id
      model_attribute :tenant_id, input: :create
      attribute :affiliation_roles, :array, data_type: :string, input: true,
                                            values_of: { association: :roles, field: :name }

      has_one :affiliation_attributes, input: true, model: :details do
        model_attribute :department, input: true
        model_attribute :title, input: true

        validates :department, presence: true
      end
    end

    validates :name, presence: true
    validates :password, presence: true, on: :create
  end

  validate_input :check_tenants
  before_save { |context| events << [:before_save, context.action] }
  around_save :wrap_save
  after_commit :record_commit, only: %i[create update]

  private

  def resource_scope
    AuthDB::User.where(tenant_id: current_tenant.id)
  end

  def check_tenants(context)
    Array(context.input.affiliations).each_with_index do |affiliation, index|
      next if affiliation.tenant_id.nil? || Tenant.exists?(affiliation.tenant_id)

      context.errors.add("affiliations[#{index}].tenant_id", :not_allowed, 'Tenant is not one you belong to')
    end
  end

  def wrap_save(context)
    events << [:around_save_start, context.action]
    yield
    events << [:around_save_end, context.changes.paths]
  end

  def record_commit(context)
    events << [:commit, context.record.id]
  end
end

class NotesController < ApplicationController
  include SchemaApi

  schema(Car, root: :note, collection_root: :notes, actions: %i[index show], touch: false) do
    model_attribute :id
    model_attribute :make
  end

  paginate :offset, limit: { default: 1, max: 2 }, count: true

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class AtomicCarsController < ApplicationController
  include SchemaApi

  schema(CarsController::CarSchema, model: Car, root: :car) do
    validates :year, presence: true
  end

  bulk atomic: true

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end

  def manufacturer_scope
    Manufacturer.where(tenant_id: current_tenant.id)
  end
end

class FleetCarsController < ApplicationController
  include SchemaApi

  cattr_accessor :touched, default: []

  schema(Car, root: :car, collection_root: :cars, touch: ->(record, changes) { touched << [record.id, changes.removed] }) do
    model_attribute :id
    model_attribute :vin, input: true
    model_attribute :model, input: true

    belongs_to :manufacturer, input: true, key: :code, render_key: true, on_put_missing: :nullify,
                              scope: -> { Manufacturer.where(tenant_id: current_tenant.id) } do
      model_attribute :name
    end

    has_many :owners, input: true do
      model_attribute :id
      model_attribute :person_id, input: true
    end

    model_attribute :created_at, format: :unix
  end

  search do
    filter :model, op: %i[starts_with null]
  end

  bulk status: ->(result) { result.all_failed? ? 422 : :ok }

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class GarageCarsController < ApplicationController
  include SchemaApi

  schema(Car, root: :car, collection_root: :cars) do
    model_attribute :id
    model_attribute :vin, input: true

    belongs_to :manufacturer, input: true, scope: :all do
      model_attribute :name
    end

    has_many :owners, input: true, on_remove: :nullify, patch: :replace do
      model_attribute :id
      model_attribute :person_id, input: true
    end
  end

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class DealerCarsController < ApplicationController
  include SchemaApi

  schema(Car, root: :car) do
    model_attribute :id
    has_many :owners, input: true, on_remove: :delete do
      model_attribute :id
      model_attribute :person_id, input: true
    end
  end
end

class StrictCarsController < ApplicationController
  include SchemaApi

  schema(Car, root: :car) do
    model_attribute :id
    has_many :owners, input: true, on_remove: :error do
      model_attribute :id
      model_attribute :person_id, input: true
    end
  end
end

class PeopleCarsController < ApplicationController
  include SchemaApi

  schema(Car, root: :car) do
    model_attribute :id
    has_many :owners, input: true, key: :person_id do
      model_attribute :id
      model_attribute :since, input: true
      belongs_to :person, input: true, scope: :all do
        model_attribute :name
      end
    end
  end

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class OwnerRecordsController < ApplicationController
  include SchemaApi

  schema(Owner, root: :owner) do
    model_attribute :id
    model_attribute :since, input: true
    belongs_to(:car, input: true, scope: -> { Car.where(tenant: current_tenant) }) { model_attribute :vin }
    belongs_to(:person, input: true, scope: :all) { model_attribute :name }
  end

  search do
    filter :person_id
  end

  upsert_key :car_id, :person_id

  private

  def resource_scope
    Owner.where(car_id: Car.where(tenant: current_tenant).select(:id))
  end
end

# includes SchemaApi once; subclasses only declare schemas
class SchemaApplicationController < ApplicationController
  include SchemaApi

  private

  def acting_user_id
    request.headers['X-User-Id']&.to_i
  end
end

class LeanCarsController < SchemaApplicationController
  schema(Car, root: :car, collection_root: :cars) do
    model_attribute :id
    model_attributes :vin, :make, input: true
    model_attribute :pin, write_only: true
    model_attribute :created_by_id, set: :acting_user_id, on: :create
    model_attribute :updated_by_id, set: ->(car) { acting_user_id || car.updated_by_id }
    attribute :owner_count, :integer, value: ->(car) { car.owners.size }, includes: :owners
    belongs_to(:manufacturer, set: :house_brand_id, on: :create) { model_attribute :name }
    timestamps
  end

  soft_delete

  private

  def house_brand_id
    Manufacturer.find_or_create_by!(tenant_id: current_tenant.id, name: 'House').id
  end

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class CarOwnersController < SchemaApplicationController
  schema(Owner, root: :owner) do
    model_attribute :id
    model_attribute :person_id, input: true
    model_attribute :since, input: true
  end

  parent :car, scope: :cars, param: :lean_car_id # nested under lean_cars

  private

  def cars
    Car.where(tenant: current_tenant)
  end
end

class TenantOwnersController < SchemaApplicationController
  schema(Owner, root: :owner) do
    model_attribute :id
  end

  parent :tenant, scope: -> { Tenant.all }
end

class PingController < SchemaApplicationController
  PingQuery = Class.new do
    include Schema::All

    def self.name
      'PingQuery'
    end

    attribute :count, :integer
    validates :count, presence: true
  end

  def show
    raise SchemaApi::Forbidden, 'Not today' if params[:deny]

    query = SchemaApi.parse!(PingQuery, request.query_parameters)
    render json: { pong: query.count }
  end
end
