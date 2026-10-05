# frozen_string_literal: true

module RequestHelpers
  def app
    TestRoutes
  end

  def tenant
    @tenant ||= Tenant.create!(name: 'Acme')
  end

  def other_tenant
    @other_tenant ||= Tenant.create!(name: 'Other')
  end

  def json_request(method, path, body = nil)
    header 'X-Tenant-Id', tenant.id.to_s
    header 'Content-Type', 'application/json'
    send(method, path, body.nil? ? nil : JSON.generate(body))
  end

  def get_json(path, params = {})
    header 'X-Tenant-Id', tenant.id.to_s
    get path, params
  end

  def json
    JSON.parse(last_response.body)
  end

  def create_car(**attributes)
    Car.create!({ tenant: tenant, vin: SecureRandom.hex(4), make: 'Ford', model: 'Bronco', year: 2020 }.merge(attributes))
  end
end
