" autoload/atattach.vim

" ========== internal state ==========
let s:started = 0

let s:at_timer = -1
let s:at_pending = 0
let s:at_pos = {}   " {bufnr, lnum, col} col is 1-based


function! atattach#HasDependencies() abort
  return exists('*fzf#run') && exists('*fzf#wrap')
endfunction

" ========== public API ==========
function! atattach#Start() abort
  if !atattach#HasDependencies()
    let g:atattach_enabled = 0
    echohl WarningMsg | echom "[atattach] disabled: fzf.vim/fzf is not available" | echohl None
    return
  endif

  if s:started
    return
  endif
  let s:started = 1
  let g:atattach_enabled = 1

  augroup AtAttach
    autocmd!
    autocmd InsertCharPre * call atattach#OnInsertCharPre()
    autocmd InsertLeave   * call atattach#CancelTimer()
  augroup END

  " Map @ only when started
  inoremap <expr> @ atattach#MaybeTrigger()
endfunction

function! atattach#Stop() abort
  if !s:started
    let g:atattach_enabled = 0
    return
  endif

  call atattach#CancelTimer()

  augroup AtAttach
    autocmd!
  augroup END

  " Remove mapping we created
  silent! iunmap @

  let s:started = 0
  let g:atattach_enabled = 0
endfunction

function! atattach#CancelTimer() abort
  if s:at_timer != -1
    call timer_stop(s:at_timer)
    let s:at_timer = -1
  endif
  let s:at_pending = 0
endfunction

function! atattach#MaybeTrigger() abort
  " If user stopped it but mapping still exists somehow, fall back to literal '@'
  if !get(g:, 'atattach_enabled', 1)
    return '@'
  endif

  call atattach#CancelTimer()

  " record position where '@' will be inserted
  let s:at_pos = {'bufnr': bufnr('%'), 'lnum': line('.'), 'col': col('.')}

  let s:at_pending = 1
  let s:at_timer = timer_start(get(g:, 'at_attach_timeout_ms', 450), function('s:OnTimeout'))
  return '@'
endfunction

function! atattach#OnInsertCharPre() abort
  " After typing '@', if user types anything else, cancel the timer (no popup)
  if s:at_pending && exists('v:char') && v:char !=# '@'
    call atattach#CancelTimer()
  endif
endfunction

" ========== implementation ==========
function! s:OnTimeout(timer_id) abort
  if !s:at_pending
    return
  endif
  let s:at_pending = 0

  " Ensure leaving Insert-mode before opening fzf (focus/input reliability)
  if mode() =~# 'i'
    call feedkeys("\<Esc>", 'n')
  endif

  call s:OpenFzfAtRoot()
endfunction

function! s:GetFzfRoot() abort
  let l:start = expand('%:p:h')
  if empty(l:start)
    let l:start = getcwd()
  endif
  return l:start
endfunction

function! s:UrlEncodePath(p) abort
  let l:s = a:p
  let l:s = substitute(l:s, '%', '%25', 'g')
  let l:s = substitute(l:s, ' ', '%20', 'g')
  let l:s = substitute(l:s, '#', '%23', 'g')
  let l:s = substitute(l:s, '?', '%3F', 'g')
  return l:s
endfunction

function! s:MakeMarkdownLink(abs_path) abort
  let l:name = fnamemodify(a:abs_path, ':t')
  let l:url = 'file:///' . s:UrlEncodePath(fnamemodify(a:abs_path, ':p'))
  return '[' . l:name . '](' . l:url . ')'
endfunction

function! s:ReplaceAtWithLink(abs_path) abort
  if empty(get(s:at_pos, 'bufnr', 0))
    return
  endif
  if !bufexists(s:at_pos.bufnr)
    return
  endif

  " jump back to the buffer where '@' was typed
  if bufnr('%') != s:at_pos.bufnr
    execute 'buffer' s:at_pos.bufnr
  endif

  let l:lnum = s:at_pos.lnum
  if l:lnum < 1 || l:lnum > line('$')
    return
  endif

  let l:line = getline(l:lnum)
  let l:c = s:at_pos.col

  " validate '@' position (allow off-by-one)
  if l:c >= 1 && l:c <= len(l:line) && l:line[l:c - 1] ==# '@'
    " ok
  else
    return
  endif

  let l:link = s:MakeMarkdownLink(a:abs_path)
  let l:new = strpart(l:line, 0, l:c - 1) . l:link . strpart(l:line, l:c)
  call setline(l:lnum, l:new)

  "" move cursor to end of inserted link and return to Insert mode (default)
  let l:cur_stop = l:c + strlen(l:link)
  call cursor(l:lnum, l:cur_stop)
  call feedkeys("\<Ignore>i", 'n')

  let s:at_pos = {}
endfunction

function! s:ToAbsPath(root, p) abort
  if a:p =~# '^\s*$'
    return ''
  endif

  " Unix abs
  if a:p[0] ==# '/'
    return fnamemodify(a:p, ':p')
  endif

  " Windows abs
  if a:p =~# '^\a\:\'
    return fnamemodify(a:p, ':p')
  endif

  return fnamemodify(a:root . '/' . a:p, ':p')
endfunction

function! s:OpenFzfAtRoot() abort
  if !exists('*fzf#run')
    echohl ErrorMsg | echom "[atattach] fzf.vim not loaded: fzf#run() missing" | echohl None
    return
  endif

  let l:root = s:GetFzfRoot()

  " Per your request: keep quotes for prompt
  let l:opts = [
        \ '--prompt', '"Attach file: "',
        \ '--walker', 'file',
        \ '--walker-root', shellescape(l:root),
        \ '--walker-skip', '.git,node_modules,dist,build,.venv,venv,target'
        \ ]

  let l:spec = {
        \ 'sink': {p -> s:ReplaceAtWithLink(s:ToAbsPath(l:root, p))},
        \ 'options': join(l:opts, ' ')
        \ }

  call fzf#run(fzf#wrap(l:spec))
endfunction
