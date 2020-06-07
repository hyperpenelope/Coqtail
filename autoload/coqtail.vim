" Author: Wolf Honore
" Coqtail Python interface and window management.

" Only source once.
if exists('g:loaded_coqtail')
  finish
endif
let g:loaded_coqtail = 1

let s:python_dir = expand('<sfile>:p:h:h') . '/python'
call coqtail#compat#init(s:python_dir)

Py from coqtail import ChannelManager, Coqtail, CoqtailServer

" Initialize global variables.
" Supported Coq versions (-1 means any number).
let s:supported = [
  \ [8, 4, -1],
  \ [8, 5, -1],
  \ [8, 6, -1],
  \ [8, 7, -1],
  \ [8, 8, -1],
  \ [8, 9, -1],
  \ [8, 10, -1],
  \ [8, 11, -1]
\]
let s:latest_supported = join(s:supported[-1][:1], '.')
" Unique suffix for auxiliary panel names.
let s:counter = 0
" Panel identifiers.
let s:no_panel = ''
let s:main_panel = 'main'
let s:goal_panel = 'goal'
let s:info_panel = 'info'
let s:aux_panels = [s:goal_panel, s:info_panel]
let s:panels = [s:main_panel] + s:aux_panels
" Default number of lines of a goal to show.
let s:goal_lines = 5
" Warning/error messages.
let s:unsupported_msg =
  \ 'Coqtail does not officially support your version of Coq (%s). ' .
  \ 'Continuing with the interface for the latest supported version (' .
  \ s:latest_supported . ').'
" Server port and channel options.
let s:port = -1
let s:chanopts = {'mode': 'json'}
" Highlighting groups.
let s:hlgroups = [
  \ ['coqtail_checked', 'CoqtailChecked'],
  \ ['coqtail_sent', 'CoqtailSent'],
  \ ['coqtail_error', 'CoqtailError']
\]

" Default Coq path.
if !exists('g:coqtail_coq_path')
  let g:coqtail_coq_path = ''
endif

" Default CoqProject file name.
if !exists('g:coqtail_project_name')
  let g:coqtail_project_name = '_CoqProject'
endif

" Default panel layout.
if !exists('g:coqtail_panel_layout')
  let g:coqtail_panel_layout = {
    \ s:goal_panel: [[s:info_panel, 'above'], [s:main_panel, 'right']],
    \ s:info_panel: [[s:goal_panel, 'below'], [s:main_panel, 'right']]
  \}
endif

" Default panel scroll options.
if !exists('g:coqtail_panel_scroll')
  let g:coqtail_panel_scroll = {
    \ s:goal_panel: 0,
    \ s:info_panel: 1
  \}
endif

" Find the path corresponding to 'lib'. Used by includeexpr.
function! coqtail#FindLib(lib) abort
  let [l:ok, l:lib] = s:callCoqtail('find_lib', 'sync', {'lib': a:lib})
  return (l:ok && l:lib != v:null) ? l:lib : a:lib
endfunction

" Open and initialize goal/info panel.
function! s:initPanel(name) abort
  let l:name = a:name . 's'
  let l:bufname = substitute(a:name, '\l', '\u\0', '')

  execute 'silent hide edit ' . l:bufname . s:counter
  setlocal buftype=nofile
  execute 'setlocal filetype=coq-' . l:name
  setlocal noswapfile
  setlocal bufhidden=hide
  setlocal nocursorline
  setlocal wrap

  let b:coqtail_panel_open = 1
  let b:coqtail_panel_size = [-1, -1]
  return bufnr('%')
endfunction

" Create buffers for the auxiliary panels.
function! s:initPanels() abort
  let l:main_buf = bufnr('%')
  let l:curpos = getcurpos()[1:]
  let l:coqtail_panel_bufs = {s:main_panel: l:main_buf}

  " Add panels
  for l:panel in s:aux_panels
    let l:coqtail_panel_bufs[l:panel] = s:initPanel(l:panel)
  endfor
  for l:buf in values(l:coqtail_panel_bufs)
    call setbufvar(l:buf, 'coqtail_panel_bufs', l:coqtail_panel_bufs)
  endfor

  " Switch back to main panel
  execute 'silent buffer ' . l:main_buf
  call cursor(l:curpos)

  let s:counter += 1
endfunction

" Detect what panel is focused.
function! s:checkPanel() abort
  if !exists('b:coqtail_panel_bufs')
    return s:no_panel
  endif

  for [l:panel, l:buf] in items(b:coqtail_panel_bufs)
    if l:buf == bufnr('%')
      return l:panel
    endif
  endfor
endfunction

" Attempt to switch to a panel.
function! s:switchPanel(panel) abort
  let l:cur_panel = s:checkPanel()

  if a:panel != l:cur_panel && a:panel != s:no_panel
    if !win_gotoid(win_getid(bufwinnr(b:coqtail_panel_bufs[a:panel])))
      return s:no_panel
    endif
  endif

  return l:cur_panel
endfunction

" Open an auxiliary panel.
function! s:openPanel(panel, force) abort
  let l:from = s:checkPanel()
  if l:from == s:no_panel
    return 0
  endif

  " Re-open only if not already open, it was open before, or 'force' is true
  let l:opened = 0
  let l:buf = b:coqtail_panel_bufs[a:panel]
  if bufwinnr(l:buf) == -1 && (a:force || getbufvar(l:buf, 'coqtail_panel_open'))
    " Arrange relative to the first open panel
    for [l:relative, l:dir] in g:coqtail_panel_layout[a:panel]
      if s:switchPanel(l:relative) != s:no_panel
        let l:dir = l:dir ==# 'above' ? 'leftabove'
          \ : l:dir ==# 'below' ? 'rightbelow'
          \ : l:dir ==# 'left' ? 'vertical leftabove'
          \ : l:dir ==# 'right' ? 'vertical rightbelow' : ''
        if l:dir !=# ''
          execute printf('silent %s sbuffer %d', l:dir, l:buf)
          let b:coqtail_panel_open = 1
          let l:opened = l:buf
          break
        endif
      endif
    endfor
  endif

  call s:switchPanel(l:from)
  return l:opened
endfunction

" Open auxiliary panels.
function! s:openPanels(force, refresh) abort
  " Open
  let l:opened = []
  for l:panel in s:aux_panels
    if s:openPanel(l:panel, a:force)
      let l:opened = add(l:opened, l:panel)
    endif
  endfor

  " Resize
  for l:panel in l:opened
    let l:buf = b:coqtail_panel_bufs[l:panel]
    let l:win = bufwinnr(l:buf)
    let l:size = getbufvar(l:buf, 'coqtail_panel_size')
    if l:size != [-1, -1]
      execute printf('vertical %dresize %d', l:win, l:size[0])
      execute printf('%dresize %d', l:win, l:size[1])
    endif
  endfor

  " Refresh
  if a:refresh
    call s:callCoqtail('refresh', 'sync', {})
  endif
endfunction

" Clear Coqtop highlighting.
function! s:clearHighlighting() abort
  for [l:var, l:_] in s:hlgroups
    if get(b:, l:var, -1) != -1
      call matchdelete(b:[l:var])
      let b:[l:var] = -1
    endif
  endfor
endfunction

" Replace the contents of 'panel' with 'txt'.
" TODO async: allow different restore behaviors
function! s:replacePanel(panel, txt, scroll) abort
  if s:switchPanel(a:panel) == s:no_panel
    return
  endif

  " Save the view
  let l:view = winsaveview()

  " Update buffer text
  silent %delete _
  call append(0, a:txt)

  " Restore the view
  if !a:scroll || !g:coqtail_panel_scroll[a:panel]
    call winrestview(l:view)
  endif
  call s:scrollPanel()
endfunction

" Refresh the highlighting and auxiliary panels.
" TODO async: main-panel only
function! coqtail#Refresh(buf, highlights, panels, scroll) abort
  if a:buf != bufnr('%')
    return
  endif
  let l:win = win_getid()

  " Update highlighting
  call s:clearHighlighting()
  for [l:var, l:grp] in s:hlgroups
    let l:hl = a:highlights[l:var]
    if l:hl != v:null
      let b:[l:var] = matchadd(l:grp, l:hl)
    endif
  endfor

  " Update panels
  for [l:panel, l:txt] in items(a:panels)
    call s:replacePanel(l:panel, l:txt, a:scroll)
  endfor
  call win_gotoid(l:win)

  redraw
endfunction

" Close auxiliary panels and clear highlighting.
function! s:hidePanels() abort
  if s:switchPanel(s:main_panel) == s:no_panel
    return
  endif

  call s:clearHighlighting()

  " Hide other panels
  let l:toclose = []
  for l:panel in s:aux_panels
    let l:buf = b:coqtail_panel_bufs[l:panel]
    let l:win = bufwinnr(l:buf)
    call setbufvar(l:buf, 'coqtail_panel_open', l:win != -1)
    call setbufvar(l:buf, 'coqtail_panel_size', [winwidth(l:win), winheight(l:win)])
    if l:win != -1
      let l:toclose = add(l:toclose, l:buf)
    endif
  endfor

  for l:buf in l:toclose
    execute bufwinnr(l:buf) . 'close!'
  endfor
endfunction

" Scroll a panel up so text doesn't go off the top of the screen.
function! s:scrollPanel() abort
  " Check if scrolling is necessary
  let l:winh = winheight(0)
  let l:disph = line('w$') - line('w0') + 1

  " Scroll
  if line('w0') != 1 && l:disph < l:winh
    normal! Gz-
  endif
endfunction

" Find the start of the nth goal.
function! s:goalStart(ngoal) abort
  return search('\m^=\+ (' . a:ngoal . ' /', 'nw')
endfunction

" Find the end of the nth goal.
function! s:goalEnd(ngoal) abort
  if s:goalStart(a:ngoal) == 0
    return 0
  endif

  let l:end = s:goalStart(a:ngoal + 1)
  return l:end != 0 ? l:end - 2 : line('$')
endfunction

" Determine the next goal's index.
function! s:goalNext() abort
  let l:goal = search('\m^=\+ (\d', 'nWbc')
  if l:goal == 0
    return 1
  else
    return matchstr(getline(l:goal), '\d\+') + 1
  endif
endfunction

" Determine the previous goal's index.
function! s:goalPrev() abort
  let l:next = s:goalNext()
  return l:next != 1 ? l:next - 2 : 0
endfunction

" Place either the start or end of the nth goal at the bottom of the window.
function! coqtail#GotoGoal(ngoal, start) abort
  let l:panel = s:switchPanel(s:goal_panel)
  if l:panel == s:no_panel
    " Failed to switch to goal panel
    return 0
  endif

  " ngoal = -1: next goal, ngoal = -2: previous goal
  let l:ngoal =
    \ a:ngoal == -1 ? s:goalNext() : a:ngoal == -2 ? s:goalPrev() : a:ngoal

  let l:sline = s:goalStart(l:ngoal)
  let l:eline = s:goalEnd(l:ngoal)
  let l:line = a:start ? l:sline : l:eline
  if l:line != 0
    if a:start
      let l:off = 1 + get(g:, 'coqtail_goal_lines', s:goal_lines)
      let l:line = min([l:line + l:off, l:eline])
    endif
    execute 'normal! ' . l:line . 'zb'
  endif

  call s:switchPanel(l:panel)
  return 1
endfunction

" Get a list of possible locations of the definition of 'target'.
function! s:findDef(target) abort
  let [l:ok, l:loc] = s:callCoqtail('find_def', 'sync', {'target': a:target})
  return (!l:ok || type(l:loc) != g:coqtail#comapt#t_list) ? v:null : l:loc
endfunction

" Populate the quickfix list with possible locations of the definition of
" 'target'.
function! coqtail#GotoDef(target, bang) abort
  let l:bang = a:bang ? '!' : ''
  let l:loc = s:findDef(a:target)
  if type(l:loc) != g:coqtail#compat#t_list
    call coqtail#util#warn('Cannot locate ' . a:target . '.')
    return
  endif
  let [l:path, l:searches] = l:loc

  " Try progressively broader searches
  let l:found_match = 0
  for l:search in l:searches
    try
      if !l:found_match
        execute 'vimgrep /\v' . l:search . '/j ' . l:path
        let l:found_match = 1
      else
        execute 'vimgrepadd /\v' . l:search . '/j ' . l:path
      endif
    catch /^Vim\%((\a\+)\)\=:E480/
    endtry
  endfor

  if l:found_match
    " Filter duplicate matches
    call coqtail#util#dedup_qfList()

    " Jump to first if possible, otherwise open list
    try
      execute 'cfirst' . l:bang
    catch /^Vim(cfirst):/
      botright cwindow
    endtry
  endif
endfunction

" Create a list of tags for 'target'.
function! coqtail#GetTags(target, flags, info) abort
  let l:loc = s:findDef(a:target)
  if type(l:loc) != g:coqtail#compat#t_list
    return v:null
  endif
  let [l:path, l:searches] = l:loc

  let l:tags = []
  for l:search in l:searches
    let l:tag = {'name': a:target, 'filename': l:path, 'cmd': '/\v' . l:search}
    let l:tags = add(l:tags, l:tag)
  endfor

  return l:tags
endfunction

" List query options for use in Coq command completion.
let s:queries = [
  \ 'Search',
  \ 'SearchAbout',
  \ 'SearchPattern',
  \ 'SearchRewrite',
  \ 'SearchHead',
  \ 'Check',
  \ 'Print',
  \ 'About',
  \ 'Locate',
  \ 'Show'
\]
function! s:queryComplete(arg, cmd, cursor) abort
  " Only complete one command
  return len(split(a:cmd)) <= 2 ? join(s:queries, "\n") : ''
endfunction

" Clean up commands, panels, and autocommands.
" TODO async: main-panel only
function! s:cleanup() abort
  " Clean up auxiliary panels
  for l:panel in s:aux_panels
    silent! execute 'bdelete' . b:coqtail_panel_bufs[l:panel]
  endfor
  silent! unlet b:coqtail_panel_bufs

  " Clean up autocmds
  silent! autocmd! coqtail#Autocmds * <buffer>

  " Clear highlighting
  call s:clearHighlighting()

  " Close the channel
  silent! call b:coqtail_chan.close()
  let b:coqtail_chan = 0
endfunction

" Get the Coq version and determine if it is supported.
function! s:checkVersion() abort
  " Check that Coq version is supported
  " Assumes message is of the following form:
  " The Coq Proof Assistant, version _._._ (_ _)
  " The 2nd '._' is optional and the 2nd '.' can also be 'pl'. Other text, such
  " as '+beta_' will be stripped and ignored by str2nr()
  let l:coqtop = 'coqtop'
  if b:coqtail_coq_path !=# ''
    let l:coqtop = b:coqtail_coq_path . '/' . l:coqtop
  endif
  let l:version_raw = split(system(l:coqtop . ' --version'))
  let l:version = l:version_raw[index(l:version_raw, 'version') + 1]
  let l:versions = map(split(l:version, '\v(\.|pl)'), 'str2nr(v:val)')

  " Pad missing version numbers with 0
  while len(l:versions) < 3
    let l:versions = add(l:versions, 0)
  endwhile

  let l:found_sup = 0
  for l:supp in s:supported
    let l:is_sup = 1

    for l:idx in range(3)
      if l:supp[l:idx] != l:versions[l:idx] && l:supp[l:idx] != -1
        let l:is_sup = 0
        break
      endif
    endfor

    if l:is_sup
      let l:found_sup = 1
      break
    endif
  endfor

  return [l:version, l:found_sup]
endfunction

" Check if the channel with Coqtail is open.
" TODO async: main-panel only
function! s:coqtailRunning() abort
  try
    let l:ok = b:coqtail_chan.status() ==# 'open'
  catch
    let l:ok = 0
  finally
    return l:ok
  endtry
endfunction

" Send a request to Coqtail.
" TODO async: main-panel only
function! s:callCoqtail(cmd, cb, args) abort
  if !s:coqtailRunning()
    return [0, -1]
  endif

  let a:args.opts = {
    \ 'encoding': &encoding,
    \ 'timeout': b:coqtail_timeout,
    \ 'filename': expand('%:p')
  \}
  let l:args = [bufnr('%'), a:cmd, a:args]

  if a:cb !=# 'sync' && g:coqtail#compat#has_channel
    " Async
    let b:cmds_pending += 1
    setlocal nomodifiable
    let l:opts = a:cb !=# '' ? {'callback': a:cb} : {'callback': 'coqtail#DefaultCB'}
    return [1, b:coqtail_chan.sendexpr(l:args, l:opts)]
  else
    " Sync
    " Don't wait for interrupt to return
    let l:opts = a:cmd ==# 'interrupt' ? {'timeout': 0} : {}
    let l:res = b:coqtail_chan.evalexpr(l:args, l:opts)
    return type(l:res) == g:coqtail#compat#t_dict
      \ ? [l:res.buf == bufnr('%'), l:res.ret]
      \ : [0, -1]
  endif
endfunction

" Print any error messages.
function! coqtail#DefaultCB(chan, msg) abort
  let b:cmds_pending -= 1
  if b:cmds_pending == 0
    setlocal modifiable
  endif
  if a:msg.ret != v:null
    call coqtail#util#err(a:msg.ret)
  endif
endfunction

" Initialize Python interface, commands, autocmds, and auxiliary panels.
function! coqtail#Start(...) abort
  if s:port == -1
    let s:port = coqtail#compat#pyeval('CoqtailServer.start_server()')
    augroup coqtail#StopServer
      autocmd! *
      autocmd VimLeavePre *
        \ call coqtail#compat#pyeval('CoqtailServer.stop_server()') | let s:port = -1
    augroup END
  endif

  if s:coqtailRunning()
    call coqtail#util#warn('Coq is already running.')
  else
    " Check if version supported
    let [b:coqtail_version, l:supported] = s:checkVersion()
    if !l:supported
      call coqtail#util#warn(printf(s:unsupported_msg, b:coqtail_version))
    endif
    let b:cmds_pending = 0

    " Open channel with Coqtail server
    let b:coqtail_chan = coqtail#channel#new(g:coqtail#compat#has_channel)
    call b:coqtail_chan.open('localhost:' . s:port, s:chanopts)

    " Check for a Coq project file
    let [b:coqtail_project_file, l:proj_args] = coqtail#coqproject#locate()

    " Prepare auxiliary panels
    call s:initPanels()
    call s:openPanels(0, 0)

    " Launch Coqtop
    let [l:ok, l:msg] = s:callCoqtail('start', 'sync', {
      \ 'version': b:coqtail_version,
      \ 'coq_path': expand(b:coqtail_coq_path),
      \ 'args': map(copy(l:proj_args + a:000), 'expand(v:val)')})
    if !l:ok || l:msg != v:null
      let l:msg = l:ok && l:msg != v:null ? l:msg : 'Failed to launch Coq.'
      call coqtail#util#err(l:msg)
      call coqtail#Stop()
      return 0
    endif

    " Draw the logo
    let l:info_win = bufwinnr(b:coqtail_panel_bufs[s:info_panel])
    call s:callCoqtail('splash', 'sync', {
      \ 'version': b:coqtail_version,
      \ 'width': winwidth(l:info_win),
      \ 'height': winheight(l:info_win)})
    call s:callCoqtail('refresh', 'sync', {})

    " Autocmds to do some detection when editing an already checked
    " portion of the code, and to hide and restore the info and goal
    " panels as needed
    augroup coqtail#Autocmds
      autocmd! * <buffer>
      autocmd InsertEnter <buffer> call s:callCoqtail('sync', 'sync', {})
      autocmd BufWinLeave <buffer> call s:hidePanels()
      autocmd BufWinEnter <buffer> call s:openPanels(0, 1)
      autocmd QuitPre <buffer> call coqtail#Stop()
    augroup END
  endif

  return 1
endfunction

" Stop the Coqtop interface and clean up auxiliary panels.
function! coqtail#Stop() abort
  call s:callCoqtail('stop', 'sync', {})
  call s:cleanup()
endfunction

" Advance/rewind Coq to the specified position.
function! coqtail#ToLine(line) abort
  " If no line was given then use the cursor's position,
  " otherwise use the last column in the line
  " TODO async: fix on multi-byte characters
  call s:callCoqtail('to_line', '', {
    \ 'line': (a:line == 0 ? line('.') : a:line) - 1,
    \ 'col': (a:line == 0 ? col('.') : len(getline(a:line))) - 1})
endfunction

" Move the cursor to the end of the region checked by Coq.
function! coqtail#JumpToEnd() abort
  let [l:ok, l:pos] = s:callCoqtail('endpoint', 'sync', {})
  if l:ok
    call cursor(l:pos)
  endif
endfunction

" Define Coqtail commands with the correct options.
let s:cmd_opts = {
  \ 'CoqStart': '-nargs=* -complete=file',
  \ 'CoqStop': '',
  \ 'CoqInterrupt': '',
  \ 'CoqNext': '-count=1',
  \ 'CoqUndo': '-count=1',
  \ 'CoqToLine': '-count=0',
  \ 'CoqToTop': '',
  \ 'CoqJumpToEnd': '',
  \ 'CoqGotoDef': '-bang -nargs=1',
  \ 'Coq': '-nargs=+ -complete=custom,s:queryComplete',
  \ 'CoqRestorePanels': '',
  \ 'CoqGotoGoal': '-bang -count=1',
  \ 'CoqGotoGoalNext': '-bang',
  \ 'CoqGotoGoalPrev': '-bang',
  \ 'CoqToggleDebug': ''
\}
function! s:cmdDef(name, act) abort
  " Start Coqtail first if needed
  let l:act = a:name !~# '\(Start\|Stop\|Interrupt\)$'
    \ ? printf('if s:coqtailRunning() || coqtail#Start() | %s | endif', a:act)
    \ : a:act
  execute printf('command! -buffer -bar %s %s %s', s:cmd_opts[a:name], a:name, l:act)
endfunction

" Define Coqtail commands.
function! s:commands() abort
  call s:cmdDef('CoqStart', 'call coqtail#Start(<f-args>)')
  call s:cmdDef('CoqStop', 'call coqtail#Stop()')
  call s:cmdDef('CoqInterrupt', 'call s:callCoqtail("interrupt", "sync", {})')
  call s:cmdDef('CoqNext', 'call s:callCoqtail("step", "", {"steps": <count>})')
  call s:cmdDef('CoqUndo', 'call s:callCoqtail("rewind", "", {"steps": <count>})')
  call s:cmdDef('CoqToLine', 'call coqtail#ToLine(<count>)')
  call s:cmdDef('CoqToTop', 'call s:callCoqtail("to_top", "", {})')
  call s:cmdDef('CoqJumpToEnd', 'call coqtail#JumpToEnd()')
  call s:cmdDef('CoqGotoDef', 'call coqtail#GotoDef(<f-args>, <bang>0)')
  call s:cmdDef('Coq', 'call s:callCoqtail("query", "", {"args": [<f-args>]})')
  call s:cmdDef('CoqRestorePanels', 'call s:openPanels(1, 1)')
  call s:cmdDef('CoqGotoGoal', 'call coqtail#GotoGoal(<count>, <bang>1)')
  call s:cmdDef('CoqGotoGoalNext', 'call coqtail#GotoGoal(-1, <bang>1)')
  call s:cmdDef('CoqGotoGoalPrev', 'call coqtail#GotoGoal(-2, <bang>1)')
  call s:cmdDef('CoqToggleDebug', 'call s:callCoqtail("toggle_debug", "", {})')
endfunction

" Define <Plug> and default mappings for Coqtail commands.
function! s:mappings() abort
  nnoremap <buffer> <silent> <Plug>CoqStart :CoqStart<CR>
  nnoremap <buffer> <silent> <Plug>CoqStop :CoqStop<CR>
  nnoremap <buffer> <silent> <Plug>CoqInterrupt :CoqInterrupt<CR>
  nnoremap <buffer> <silent> <Plug>CoqNext :<C-U>execute v:count1 'CoqNext'<CR>
  nnoremap <buffer> <silent> <Plug>CoqUndo :<C-U>execute v:count1 'CoqUndo'<CR>
  nnoremap <buffer> <silent> <Plug>CoqToLine :<C-U>execute v:count 'CoqToLine'<CR>
  nnoremap <buffer> <silent> <Plug>CoqToTop :CoqToTop<CR>
  nnoremap <buffer> <silent> <Plug>CoqJumpToEnd :CoqJumpToEnd<CR>
  inoremap <buffer> <silent> <Plug>CoqNext <C-\><C-o>:CoqNext<CR>
  inoremap <buffer> <silent> <Plug>CoqUndo <C-\><C-o>:CoqUndo<CR>
  inoremap <buffer> <silent> <Plug>CoqToLine <C-\><C-o>:CoqToLine<CR>
  inoremap <buffer> <silent> <Plug>CoqToTop <C-\><C-o>:CoqToTop<CR>
  inoremap <buffer> <silent> <Plug>CoqJumpToEnd <C-\><C-o>:CoqJumpToEnd<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoDef :CoqGotoDef <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqSearch :Coq Search <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqCheck :Coq Check <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqAbout :Coq About <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqPrint :Coq Print <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqLocate :Coq Locate <C-r>=<SID>getCurWord()<CR><CR>
  nnoremap <buffer> <silent> <Plug>CoqRestorePanels :CoqRestorePanels<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalStart :<C-U>execute v:count1 'CoqGotoGoal'<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalEnd :<C-U>execute v:count1 'CoqGotoGoal!'<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalNextStart :CoqGotoGoalNext<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalNextEnd :CoqGotoGoalNext!<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalPrevStart :CoqGotoGoalPrev<CR>
  nnoremap <buffer> <silent> <Plug>CoqGotoGoalPrevEnd :CoqGotoGoalPrev!<CR>
  nnoremap <buffer> <silent> <Plug>CoqToggleDebug :CoqToggleDebug<CR>

  " Use default mappings unless user opted out
  if get(g:, 'coqtail_nomap', 0)
    return
  endif

  let l:maps = [
    \ ['Start', 'c', 'n'],
    \ ['Stop', 'q', 'n'],
    \ ['Interrupt', '!<C-c>', 'n'],
    \ ['Next', 'j', 'ni'],
    \ ['Undo', 'k', 'ni'],
    \ ['ToLine', 'l', 'ni'],
    \ ['ToTop', 'T', 'ni'],
    \ ['JumpToEnd', 'G', 'ni'],
    \ ['GotoDef', 'g', 'n'],
    \ ['Search', 's', 'n'],
    \ ['Check', 'h', 'n'],
    \ ['About', 'a', 'n'],
    \ ['Print', 'p', 'n'],
    \ ['Locate', 'f', 'n'],
    \ ['RestorePanels', 'r', 'ni'],
    \ ['GotoGoalStart', 'gg', 'ni'],
    \ ['GotoGoalEnd', 'GG', 'ni'],
    \ ['GotoGoalNextStart', '!g]', 'n'],
    \ ['GotoGoalNextEnd', '!G]', 'n'],
    \ ['GotoGoalPrevStart', '!g[', 'n'],
    \ ['GotoGoalPrevEnd', '!G[', 'n'],
    \ ['ToggleDebug', 'd', 'n']
  \]

  for [l:cmd, l:key, l:types] in l:maps
    for l:type in split(l:types, '\zs')
      if !hasmapto('<Plug>Coq' . l:cmd, l:type)
        let l:prefix = '<leader>c'
        if l:key[0] ==# '!'
          let l:key = l:key[1:]
          let l:prefix = ''
        endif
        execute l:type . 'map <buffer> ' . l:prefix . l:key . ' <Plug>Coq' . l:cmd
      endif
    endfor
  endfor
endfunction

" Initialize buffer local variables, commands, and mappings.
function! coqtail#Register() abort
  " Initialize once
  if !exists('b:coqtail_chan')
    let b:coqtail_chan = 0
    for [l:var, l:_] in s:hlgroups
      let b:[l:var] = -1
    endfor
    let b:coqtail_timeout = 0
    let b:coqtail_log_name = ''
    if !exists('b:coqtail_coq_path')
      let b:coqtail_coq_path = g:coqtail_coq_path
    endif

    call s:commands()
    call s:mappings()
  endif
endfunction
