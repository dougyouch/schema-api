# frozen_string_literal: true

namespace :auth do
  desc 'Create an application and print its token (shown once): rails auth:create_application[billing]'
  task :create_application, [:name] => :environment do |_task, args|
    application, token = AuthDB::Application.issue!(args.fetch(:name))
    puts "application #{application.id} (#{application.name}): #{token}"
  end
end
