require "rails_helper"

# Estes cenarios existem como request spec, e nao como spec de sistema, porque
# dependem de forjar parametros que um navegador nunca enviaria. Os fluxos de
# usuario ficam em spec/system.
RSpec.describe "Autorizacao", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "visitante nao autenticado" do
    it "e redirecionado ao tentar listar" do
      get lists_path

      expect(response).to redirect_to(login_path)
    end

    it "nao consegue criar lista" do
      expect do
        post lists_path, params: { list: { name: "Invadida" } }
      end.not_to change(List, :count)

      expect(response).to redirect_to(login_path)
    end

    it "nao consegue criar tarefa" do
      list = create(:list, user: owner)

      expect do
        post list_tasks_path(list), params: { task: { title: "Invadida" } }
      end.not_to change(Task, :count)

      expect(response).to redirect_to(login_path)
    end

    it "nao consegue destruir lista" do
      list = create(:list, user: owner)

      expect do
        delete list_path(list)
      end.not_to change(List, :count)
    end
  end

  describe "posse vem do token de sessao, nunca do payload" do
    before { sign_in_via_request(owner) }

    it "ignora user_id enviado na criacao da lista" do
      post lists_path, params: { list: { name: "Mercado", user_id: other_user.id } }

      expect(List.last.user_id).to eq(owner.id)
    end

    it "nao permite transferir a lista para outro usuario" do
      list = create(:list, user: owner)

      patch list_path(list), params: { list: { name: "Nova", user_id: other_user.id } }

      expect(list.reload.user_id).to eq(owner.id)
    end

    it "ignora list_id enviado na criacao da tarefa e usa a lista da rota" do
      list = create(:list, user: owner)
      list_alheia = create(:list, user: other_user)

      post list_tasks_path(list), params: { task: { title: "Comprar leite", list_id: list_alheia.id } }

      expect(Task.last.list_id).to eq(list.id)
      expect(list_alheia.tasks).to be_empty
    end

    it "nao permite mover a tarefa para outra lista" do
      list = create(:list, user: owner)
      list_alheia = create(:list, user: other_user)
      task = create(:task, list: list)

      patch list_task_path(list, task), params: { task: { title: "Movida", list_id: list_alheia.id } }

      expect(task.reload.list_id).to eq(list.id)
    end

    it "ignora role enviado no cadastro" do
      post signup_path, params: { user: { username: "novo", email: "novo@example.com", password: "senha_super_secreta", role: "admin" } }

      expect(User.find_by(email: "novo@example.com").role).to eq("user")
    end
  end

  describe "recurso de outro usuario e indistinguivel de inexistente" do
    before { sign_in_via_request(owner) }

    it "responde igual para lista alheia e lista inexistente" do
      list_alheia = create(:list, user: other_user)

      get list_path(list_alheia)
      alheia = [ response.status, response.body ]

      get "/lists/999999"
      inexistente = [ response.status, response.body ]

      # Um 403 aqui confirmaria que o id existe, permitindo varrer os ids
      # para descobrir quais listas os outros usuarios possuem.
      expect(alheia).to eq(inexistente)
      expect(response).to have_http_status(:not_found)
    end

    it "responde 404 ao tentar editar lista alheia" do
      list_alheia = create(:list, user: other_user, name: "Intocada")

      patch list_path(list_alheia), params: { list: { name: "Invadida" } }

      expect(response).to have_http_status(:not_found)
      expect(list_alheia.reload.name).to eq("Intocada")
    end

    it "responde 404 ao tentar destruir lista alheia" do
      list_alheia = create(:list, user: other_user)

      expect do
        delete list_path(list_alheia)
      end.not_to change(List, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "responde 404 ao tentar criar tarefa em lista alheia" do
      list_alheia = create(:list, user: other_user)

      expect do
        post list_tasks_path(list_alheia), params: { task: { title: "Invadida" } }
      end.not_to change(Task, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "responde 404 ao tentar destruir tarefa de lista alheia" do
      list_alheia = create(:list, user: other_user)
      task = create(:task, list: list_alheia)

      expect do
        delete list_task_path(list_alheia, task)
      end.not_to change(Task, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "responde 404 para tarefa que existe mas nao pertence a lista da rota" do
      list = create(:list, user: owner)
      outra_lista_minha = create(:list, user: owner)
      task = create(:task, list: outra_lista_minha)

      get list_task_path(list, task)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "login nao revela quais emails existem" do
    let!(:user) { create(:user, email: "ana@example.com") }

    it "responde de forma identica para senha errada e email inexistente" do
      post login_path, params: { email: "ana@example.com", password: "senha_errada_1" }
      senha_errada = [ response.status, response.body ]

      post login_path, params: { email: "ninguem@example.com", password: "senha_errada_1" }
      email_inexistente = [ response.status, response.body ]

      expect(senha_errada).to eq(email_inexistente)
    end

    it "gasta uma comparacao bcrypt mesmo quando o email nao existe" do
      # Sem isto o caminho do email inexistente retorna sem rodar bcrypt, e a
      # diferenca de tempo revela quais emails estao cadastrados.
      expect(BCrypt::Password).to receive(:new)
        .with(SessionsController::DUMMY_PASSWORD_DIGEST)
        .and_call_original

      post login_path, params: { email: "ninguem@example.com", password: "qualquer_coisa" }
    end
  end

  describe "protecao CSRF" do
    it "esta habilitada na aplicacao" do
      # O modo API nao tinha CSRF porque nao havia cookie de sessao. Com
      # sessao, essa protecao volta a ser a defesa principal.
      expect(ApplicationController.forgery_protection_strategy).to be_present
    end
  end
end
