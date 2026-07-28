require "rails_helper"

# V-01: tentativas de login ilimitadas. Com bcrypt em 3 threads do Puma, isso e
# ao mesmo tempo credential stuffing barato e um amplificador de DoS - e a
# defesa de timing (DUMMY_PASSWORD_DIGEST) garante que ate e-mail inexistente
# custe um bcrypt completo, o que barateia ainda mais o DoS.
RSpec.describe "Rate limiting", type: :request do
  describe "login" do
    let!(:owner) { create(:user, email: "ana@example.com") }

    it "aceita tentativas ate o limite" do
      10.times { post login_path, params: { email: owner.email, password: "errada_1" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "bloqueia a partir da 11a tentativa em 3 minutos" do
      11.times { post login_path, params: { email: owner.email, password: "errada_1" } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "explica o bloqueio em vez de devolver uma pagina vazia" do
      11.times { post login_path, params: { email: owner.email, password: "errada_1" } }

      expect(response.body).to include("Muitas tentativas")
    end

    it "libera de novo depois da janela" do
      11.times { post login_path, params: { email: owner.email, password: "errada_1" } }
      expect(response).to have_http_status(:too_many_requests)

      travel 4.minutes
      post login_path, params: { email: owner.email, password: AuthHelpers::DEFAULT_PASSWORD }

      expect(response).to redirect_to(lists_path)
    end

    it "aplica o mesmo limite para e-mail existente e inexistente" do
      # Senao o proprio rate limit vira o oraculo de enumeracao que o
      # DUMMY_PASSWORD_DIGEST fecha: quem existe bloquearia num ponto e quem
      # nao existe em outro.
      11.times { post login_path, params: { email: owner.email, password: "errada_1" } }
      status_existente = response.status

      travel 4.minutes
      11.times { post login_path, params: { email: "ninguem@example.com", password: "errada_1" } }

      expect(response.status).to eq(status_existente)
    end

    it "conta por IP, e nao por e-mail" do
      # Limitar por e-mail deixaria um atacante travar a conta de terceiros de
      # proposito (DoS por lockout) e ainda revelaria quais e-mails existem.
      6.times { post login_path, params: { email: owner.email, password: "errada_1" } }
      6.times { post login_path, params: { email: "outro@example.com", password: "errada_1" } }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "cadastro" do
    def signup(n)
      post signup_path, params: { user: { username: "usuario#{n}",
                                          email: "usuario#{n}@example.com",
                                          password: "senha_super_secreta",
                                          password_confirmation: "senha_super_secreta" } }
    end

    it "aceita cadastros ate o limite" do
      5.times { |n| signup(n) }

      expect(response).to redirect_to(lists_path)
    end

    it "bloqueia a partir do 6o cadastro em uma hora" do
      6.times { |n| signup(n) }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "explica o bloqueio" do
      6.times { |n| signup(n) }

      expect(response.body).to include("Muitos cadastros")
    end
  end
end
