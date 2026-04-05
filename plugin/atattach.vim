" plugin/atattach.vim
if exists('g:loaded_atattach')
  finish
endif
let g:loaded_atattach = 1

" ===== Defaults (user may override in vimrc) =====
if !exists('g:at_attach_timeout_ms')
  let g:at_attach_timeout_ms = 450
endif

" Default fzf popup layout (Vim 9 popup)
if !exists('g:fzf_layout')
  let g:fzf_layout = { 'window': { 'width': 0.90, 'height': 0.60 } }
endif

" Enabled by default
if !exists('g:atattach_enabled')
  let g:atattach_enabled = 1
endif

" 保存依赖检查结果
let g:atattach_dependencies_ok = 0

function! s:AtAttachCheckDependencies() abort
  " 只检查 fzf.vim 是否已加载并暴露核心函数
  if exists('*fzf#run') && exists('*fzf#wrap')
    return 1
  endif
  return 0
endfunction

let g:atattach_dependencies_ok = s:AtAttachCheckDependencies()

" ===== User commands: 开/关 =====
command! AtAttachStart call atattach#Start()
command! AtAttachStop  call atattach#Stop()

" Start immediately if enabled
if get(g:, 'atattach_enabled', 1)
  call atattach#Start()
endif
