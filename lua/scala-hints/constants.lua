return {
  source = 'scala-hints',
  diagnostic_namespace = 'scala-hints',
  lang = 'scala',
  client_name = 'scala-hints-lsp',
  capabilities = {
    textDocumentSync = {
      openClose = true,
      change = 1,
    },
    codeActionProvider = {
      resolveProvider = false,
    },
  },
}
