# frozen_string_literal: true

# 401 in SchemaApi's error format: no valid session or application token.
class Unauthorized < SchemaApi::Error
  CODE = 'unauthorized'
  STATUS = :unauthorized
end
