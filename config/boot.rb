ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
# bootsnap removido: seu cache nativo nao abre arquivos sob um caminho com
# acento ("Area de Trabalho") no Windows, quebrando o boot da aplicacao.
