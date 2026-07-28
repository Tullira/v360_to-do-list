require "rails_helper"

# V-11: `validates :uniqueness` faz um SELECT antes do INSERT. Dois cadastros
# simultaneos com o mesmo e-mail passam os dois pela validacao e o segundo bate
# no indice unico do banco.
#
# A corrida nao da para reproduzir de forma deterministica numa suite de um
# processo so, entao o gatilho e simulado: o que esta sob teste e o tratamento
# do RecordNotUnique, nao o escalonador do Postgres.
RSpec.describe "Cadastro simultaneo com o mesmo e-mail", type: :request do
  let(:params) do
    { user: { username: "ana", email: "ana@example.com", password: "senha_super_secreta" } }
  end

  it "devolve 422 em vez de 500 quando o indice unico do banco perde a corrida" do
    allow_any_instance_of(User).to receive(:save)
      .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint"))

    post signup_path, params: params

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "explica o motivo em vez de mostrar uma pagina de erro" do
    allow_any_instance_of(User).to receive(:save)
      .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint"))

    post signup_path, params: params

    expect(response.body).to include("Email ja esta em uso")
  end

  it "nao autentica ninguem quando o cadastro falha na corrida" do
    allow_any_instance_of(User).to receive(:save)
      .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint"))

    post signup_path, params: params
    get lists_path

    expect(response).to redirect_to(login_path)
  end
end
