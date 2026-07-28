import { Controller } from "@hotwired/stimulus"

// Envia o formulario assim que o campo muda.
//
// Existe para tirar o onchange="this.form.requestSubmit()" das views: handler
// inline so funciona com 'unsafe-inline' em script-src, e essa unica palavra
// esvaziaria a CSP inteira - qualquer XSS voltaria a executar.
//
// O eagerLoadControllersFrom em controllers/index.js registra este arquivo
// sozinho; nao ha nada a declarar em lugar nenhum.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
