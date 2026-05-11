module Api
  class TemplatesController < BaseController
    include Authorizable
    TEMPLATES = [
      {
        id: 'rails-api',
        name: 'Rails API',
        category: 'stack',
        description: 'Ruby on Rails API with PostgreSQL and Redis',
        services: [
          { name: 'web', subtype: 'rails', type: 'app', category: 'app' },
          { name: 'database', subtype: 'postgres', type: 'database', category: 'database' },
          { name: 'cache', subtype: 'redis', type: 'cache', category: 'cache' },
        ]
      },
      {
        id: 'nodejs-app',
        name: 'Node.js App',
        category: 'stack',
        description: 'Node.js application with MongoDB',
        services: [
          { name: 'web', subtype: 'node', type: 'app', category: 'app' },
          { name: 'database', subtype: 'mongo', type: 'database', category: 'database' },
        ]
      },
      {
        id: 'python-django',
        name: 'Python Django',
        category: 'stack',
        description: 'Django application with PostgreSQL',
        services: [
          { name: 'web', subtype: 'python', type: 'app', category: 'app' },
          { name: 'database', subtype: 'postgres', type: 'database', category: 'database' },
        ]
      },
      {
        id: 'wordpress',
        name: 'WordPress',
        category: 'stack',
        description: 'WordPress with MySQL',
        services: [
          { name: 'web', subtype: 'php', type: 'app', category: 'app' },
          { name: 'database', subtype: 'mysql', type: 'database', category: 'database' },
        ]
      },
    ]

    def index
      render json: TEMPLATES
    end

    def deploy
      template = TEMPLATES.find { |t| t[:id] == params[:id] }
      return render json: { error: 'Template not found' }, status: :not_found unless template

      project = scoped_projects.find_by(id: params[:project_id])
      return render json: { error: 'Project not found' }, status: :not_found unless project

      created = template[:services].map do |svc|
        is_app = svc[:type] == 'app'
        service = project.services.create!(
          name: svc[:name],
          service_type: svc[:type],
          subtype: svc[:subtype],
          status: 'stopped',
          builder: is_app ? 'nixpacks' : nil,
        )
        if is_app
          service.process_types.create!(name: 'web', quantity: 1, running: 0, command: '')
        end
        service
      end

      render json: {
        created: created.map { |s| { id: s.id, name: s.name, type: s.service_type, subtype: s.subtype } }
      }
    end
  end
end
