# frozen_string_literal: true

# a callback that renders instead of raising, and one that raises for show only
class GuardedNotesController < ApplicationController
  include SchemaApi

  before_action { head :unauthorized unless request.headers['X-Let-In'] }
  before_action(only: :show) { raise SchemaApi::Forbidden, 'Notes are only listed' }

  schema(Car, root: :guarded_note, collection_root: :guarded_notes, actions: %i[index show]) do
    model_attribute :id
  end

  private

  def resource_scope
    Car.where(tenant: current_tenant)
  end
end

class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources CarsController, NotesController, GuardedNotesController, UsersController
end
