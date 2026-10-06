# frozen_string_literal: true

# Demo data and two tokens to try queries with, until mutations can log in and create records.
#   bin/rails db:seed
# db:prepare also seeds a new database; specs make their own data.
return if Rails.env.test? || AuthDB::User.exists?

acme = AuthDB::Organization.create!(name: 'Acme', slug: 'acme')
globex = AuthDB::Organization.create!(name: 'Globex', slug: 'globex')
ada = AuthDB::User.create!(name: 'Ada', email: 'ada@example.com', password: 'secret-password')
grace = AuthDB::User.create!(name: 'Grace', email: 'grace@example.com', password: 'secret-password')
linus = AuthDB::User.create!(name: 'Linus', email: 'linus@example.com', password: 'secret-password')
ada.affiliations.create!(organization: acme).create_affiliation_attribute!(department: 'Engineering', title: 'Lead')
grace_at_acme = grace.affiliations.create!(organization: acme)
grace_at_acme.create_affiliation_attribute!(department: 'Engineering', title: 'Engineer', manager_user: ada)
linus.affiliations.create!(organization: globex)

_application, app_token = AuthDB::Application.issue!('seed')
session = ada.sessions.new(ip_address: '127.0.0.1', user_agent: 'seed')
session.issue_token!(1.day)
session.save!

puts "X-Application-Token: #{app_token}"
puts "Authorization: Bearer #{session.token}   (Ada, good for a day)"
