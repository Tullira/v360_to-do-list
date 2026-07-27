require "rails_helper"

# Cenario de request spec, e nao de sistema, porque no navegador ele depende de
# uma corrida: o prefetch e a navegacao real disputam o cookie de sessao. Aqui a
# sequencia e deterministica.
RSpec.describe "Flash e prefetch do Turbo", type: :request do
  it "nao deixa o prefetch consumir a mensagem antes de o usuario ver a pagina" do
    # 1. Visitante tenta abrir as listas e e mandado para o login com a mensagem.
    get lists_path
    expect(response).to redirect_to(login_path)

    # 2. O mouse passa por cima de um link e o Turbo faz prefetch. Essa
    #    requisicao nao e uma visita: o usuario nunca ve essa resposta.
    get signup_path, headers: { "X-Sec-Purpose" => "prefetch" }

    # 3. A navegacao real chega. A mensagem tem que estar la.
    get login_path
    expect(response.body).to include("Faca login para continuar")
  end

  it "nao deixa o prefetch reescrever o cookie de sessao" do
    # O prefetch corre em paralelo com a navegacao real. Se ele responder com
    # Set-Cookie, a sessao que ele carregava (buscada antes, sem a mensagem)
    # sobrescreve a mais nova e apaga o flash - mesmo com flash.keep, porque
    # essa requisicao nunca chegou a ver a mensagem.
    get lists_path
    get signup_path, headers: { "X-Sec-Purpose" => "prefetch" }

    expect(Array(response.headers["Set-Cookie"]).join("\n")).not_to include("session")
  end

  it "consome a mensagem normalmente numa navegacao de verdade" do
    get lists_path
    get login_path
    expect(response.body).to include("Faca login para continuar")

    # Recarregar nao pode repetir a mensagem indefinidamente.
    get login_path
    expect(response.body).not_to include("Faca login para continuar")
  end
end
