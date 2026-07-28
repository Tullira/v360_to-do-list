require "rails_helper"

# V-02: nenhum cabecalho Content-Security-Policy era enviado.
RSpec.describe "Content-Security-Policy", type: :request do
  let(:owner) { create(:user) }

  def csp
    response.headers["Content-Security-Policy"]
  end

  it "envia o cabecalho nas paginas autenticadas" do
    sign_in_via_request(owner)
    get lists_path

    expect(csp).to be_present
  end

  it "envia o cabecalho tambem para visitante" do
    get login_path

    expect(csp).to be_present
  end

  it "nao permite 'unsafe-inline' em lugar nenhum" do
    # Uma unica ocorrencia esvaziaria a protecao: e por isso que os dois
    # onchange inline viraram um controller Stimulus antes desta politica.
    sign_in_via_request(owner)
    get lists_path

    expect(csp).not_to include("unsafe-inline")
  end

  it "nao permite 'unsafe-eval'" do
    sign_in_via_request(owner)
    get lists_path

    expect(csp).not_to include("unsafe-eval")
  end

  it "restringe script-src a origem propria" do
    sign_in_via_request(owner)
    get lists_path

    expect(csp).to include("script-src 'self'")
  end

  it "bloqueia object-src e frame-ancestors" do
    sign_in_via_request(owner)
    get lists_path

    expect(csp).to include("object-src 'none'")
    expect(csp).to include("frame-ancestors 'none'")
  end

  it "emite um nonce preenchido ja na primeira visita" do
    # Nonce vazio bloquearia o <script type="importmap">, que e inline, e
    # deixaria o primeiro acesso de qualquer visitante sem JavaScript nenhum.
    get login_path

    expect(response.body).to match(/<meta name="csp-nonce" content="[^"]+"/)
    expect(csp).to match(/script-src 'self' 'nonce-[^']+'/)
  end

  it "mantem as duas respostas 404 identicas byte a byte" do
    # O nonce sai do id da sessao justamente para nao quebrar isto. Com um
    # nonce sorteado por requisicao, as duas respostas passariam a diferir e o
    # 404 generico deixaria de esconder quais ids existem.
    sign_in_via_request(owner)
    list_alheia = create(:list, user: create(:user))

    get list_path(list_alheia)
    alheia = [ response.status, response.body ]

    get "/lists/999999"
    inexistente = [ response.status, response.body ]

    expect(alheia).to eq(inexistente)
  end
end
