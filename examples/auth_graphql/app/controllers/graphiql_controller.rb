# frozen_string_literal: true

# GET /graphiql in development: an in-browser IDE for POST /graphql. Put a token in its
# Headers tab, e.g. { "X-Application-Token": "app_..." }.
class GraphiqlController < ActionController::API
  PAGE = <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Auth GraphiQL</title>
        <link rel="stylesheet" href="https://unpkg.com/graphiql@3/graphiql.min.css">
        <style>body { margin: 0; height: 100vh; } #graphiql { height: 100vh; }</style>
      </head>
      <body>
        <div id="graphiql"></div>
        <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
        <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
        <script crossorigin src="https://unpkg.com/graphiql@3/graphiql.min.js"></script>
        <script>
          const fetcher = GraphiQL.createFetcher({ url: '/graphql' });
          ReactDOM.createRoot(document.getElementById('graphiql'))
            .render(React.createElement(GraphiQL, { fetcher, defaultEditorToolsVisibility: 'headers' }));
        </script>
      </body>
    </html>
  HTML

  def show
    render html: PAGE.html_safe
  end
end
