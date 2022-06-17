command! -nargs=1 SearchExternalAssembliesForType :call luaeval("require('Omnisharp-lua').StartSearchExternalAssembliesForType(_A)", expand('<cword>'))
command! -nargs=1 -complete=dir AddExternalAssemblyDirectory :call luaeval("require('Omnisharp-lua').StartAddExternalDirectory(_A)", <f-args>)
command -nargs=1 SearchForType :call luaeval("require('Omnisharp-lua').StartGetAllTypes(_A)", <q-args>)
command OpenDecompilerLog :e c:\Users\\eric\AppData\Local\nvim-data\csdecompile.log | set wrap
command StartDecompiler :lua require('Omnisharp-lua').StartDecompiler()
