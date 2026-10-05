# frozen_string_literal: true

RSpec.describe 'sessions' do
  let!(:user) { create_user }

  it 'logs in with email and password and returns a token good for an hour' do
    post '/sessions', params: body(session: { email: ' ADA@example.com ', password: 'secret-password' }),
                      headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:created)
    expect(json['session']).to include('token' => a_kind_of(String),
                                       'user' => { 'id' => user.id, 'name' => 'Ada',
                                                   'email' => 'ada@example.com' })
    expect(json['session']).not_to have_key('password')
    expect(Time.iso8601(json['session']['expires_at'])).to be_within(5.seconds).of(1.hour.from_now)
  end

  it 'is a 401 for a wrong password, and a 422 when fields are missing' do
    post '/sessions', params: body(session: { email: user.email, password: 'nope' }),
                      headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
    expect(json['error']).to include('code' => 'unauthorized', 'message' => 'Email or password is incorrect')

    post '/sessions', params: body(session: { email: user.email }), headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']['details']).to eq([{ 'field' => 'password', 'error' => 'blank',
                                              'message' => "Password can't be blank" }])
    expect(AuthDB::Session.count).to eq(0)
  end

  it 'shows the current session, lists active ones, and logs out' do
    headers = user_headers(user)
    get '/sessions/current', headers: headers
    expect(json['session']).to include('token' => nil, 'user' => include('id' => user.id))

    get '/sessions', headers: headers
    expect(json['sessions'].size).to eq(1)

    delete '/sessions/current', headers: headers
    expect(response).to have_http_status(:no_content)
    get '/sessions/current', headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'expires tokens after an hour' do
    headers = user_headers(user)
    travel 61.minutes do
      get '/sessions/current', headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
