import { Controller } from "@hotwired/stimulus"

// Popup de criacao. Usa o <dialog> nativo: ele ja da foco preso, fecha no Esc
// e sobe para a top layer sem precisar de z-index nem de biblioteca externa.
//
// O gatilho fica fora do <dialog>, entao o controller vive num wrapper que
// envolve os dois - acoes do Stimulus so chegam a controllers ancestrais.
export default class extends Controller {
  static targets = ["panel"]
  static values = { open: Boolean }

  connect() {
    // Quando a validacao falha, o servidor re-renderiza a pagina inteira com
    // status 422 e o Turbo troca o body. Sem isto o popup voltaria fechado,
    // escondendo o erro e o que a pessoa ja tinha digitado.
    if (this.openValue) this.open()
  }

  open() {
    this.panelTarget.showModal()
  }

  close() {
    this.panelTarget.close()
  }

  // Clique no backdrop: o event.target e o proprio <dialog> apenas quando o
  // clique cai fora do conteudo, entao isto nao fecha ao clicar no formulario.
  closeOnBackdrop(event) {
    if (event.target === this.panelTarget) this.close()
  }
}
