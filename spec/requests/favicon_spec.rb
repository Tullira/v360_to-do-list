require "rails_helper"

# O layout nao declarava icone nenhum: o navegador pedia /favicon.ico, tomava
# 404 e a aba ficava com o icone generico. Os arquivos vivem em public/ (e nao
# em app/assets) porque o href precisa ser um caminho fixo, sem digest - e o
# proprio navegador quem os busca, sem passar pelo Propshaft.
RSpec.describe "Favicon", type: :request do
  it "declara o icone SVG no layout" do
    get login_path

    expect(response.body).to include(
      %(<link rel="icon" href="/icon.svg" type="image/svg+xml">)
    )
  end

  it "declara o PNG como alternativa e como apple-touch-icon" do
    # Safari e a tela de inicio do iOS nao usam o SVG.
    get login_path

    expect(response.body).to include(%(<link rel="icon" href="/icon.png" type="image/png">))
    expect(response.body).to include(%(<link rel="apple-touch-icon" href="/icon.png">))
  end

  it "serve os dois arquivos" do
    # Um href que responde 404 e pior que nenhum: o navegador ainda cai no
    # icone generico, so que depois de duas requisicoes perdidas.
    get "/icon.svg"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/svg+xml")

    get "/icon.png"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end

  it "mantem o icone dentro do que a CSP permite" do
    # img_src 'self' data: - o icone e servido pela propria origem, entao
    # nenhuma diretiva precisa ser afrouxada por causa dele.
    get login_path

    expect(response.headers["Content-Security-Policy"]).to include("img-src 'self' data:")
  end
end
