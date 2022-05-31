command SearchExternalAssembliesForType :call luaeval("require('Omnisharp-lua').StartSearchExternalAssembliesForType(_A)", expand('<cword>'))
command! -nargs=1 -complete=dir AddExternalAssemblyDirectory :call luaeval("require('Omnisharp-lua').StartAddExternalDirectory(_A)", <f-args>)
