require "rails_helper"

# V-03: a sessao nao tinha prazo de validade. Sao duas camadas, e elas nao sao
# redundantes por acaso:
#
# 1. `expire_after` no cookie store. Nao e so uma dica ao navegador: o Rails
#    embute a expiracao dentro do proprio cookie assinado, entao o servidor
#    recusa o cookie vencido mesmo que o cliente ignore o atributo Expires e
#    reenvie assim mesmo.
#
# 2. O carimbo `session[:created_at]`, conferido em SessionManagement. Com as
#    duas janelas iguais, a camada 1 sempre reprova primeiro - por isso os
#    testes da camada 2 encurtam SESSION_MAX_AGE, senao estariam testando a
#    camada 1 de novo achando que testam a 2.
RSpec.describe "Expiracao de sessao", type: :request do
  let(:owner) { create(:user) }

  describe "prazo do cookie assinado" do
    it "mantem a sessao valida dentro do prazo" do
      sign_in_via_request(owner)

      travel 13.days
      get lists_path

      expect(response).to have_http_status(:ok)
    end

    it "recusa a sessao depois de duas semanas" do
      sign_in_via_request(owner)

      travel 2.weeks + 1.day
      get lists_path

      expect(response).to redirect_to(login_path)
    end

    it "continua recusando em requisicoes seguintes" do
      sign_in_via_request(owner)

      travel 2.weeks + 1.day
      get lists_path
      get lists_path

      expect(response).to redirect_to(login_path)
    end
  end

  describe "carimbo conferido no servidor" do
    # Janela curta para que ESTA camada seja a que reprova. Com as duas em
    # 2.weeks o cookie venceria primeiro e o teste passaria sem exercitar nada.
    before { stub_const("SessionManagement::SESSION_MAX_AGE", 1.hour) }

    it "recusa a sessao passada do prazo do carimbo" do
      sign_in_via_request(owner)

      travel 2.hours
      get lists_path

      expect(response).to redirect_to(login_path)
    end

    it "avisa que a sessao expirou, em vez de so mandar fazer login" do
      sign_in_via_request(owner)

      travel 2.hours
      get lists_path
      follow_redirect!

      expect(response.body).to include("Sua sessao expirou")
    end

    it "mantem a sessao valida dentro do prazo do carimbo" do
      sign_in_via_request(owner)

      travel 30.minutes
      get lists_path

      expect(response).to have_http_status(:ok)
    end

    it "descarta o cookie vencido em vez de so ignora-lo" do
      # Sem o reset_session o cookie velho continuaria viajando em toda
      # requisicao seguinte.
      sign_in_via_request(owner)

      travel 2.hours
      get lists_path

      expect(Array(response.headers["Set-Cookie"]).join("\n")).to include("_to_do_list_session")
    end
  end
end
