command! -nargs=1 -complete=dir AddExternalAssemblyDirectory :call luaeval("require('Omnisharp-lua').StartAddExternalDirectory(_A)", <f-args>)
command -nargs=1 SearchForType :call luaeval("require('Omnisharp-lua').StartGetAllTypes(_A)", <q-args>)
command OpenDecompilerLog :lua require('Omnisharp-lua').OpenLog()
command StartDecompiler :lua require('Omnisharp-lua').StartDecompiler()
