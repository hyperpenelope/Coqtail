" Author: Wolf Honore
" Locate and parse _CoqProject files.

Py import shlex

" Parse a _CoqProject file into options that can be passed to Coqtop.
function! coqtail#coqproject#parse(file) abort
  let l:dir = fnamemodify(a:file, ':p:h')
  let l:dir_opts = {'-R': 2, '-Q': 2, '-I': 1, '-include': 1}

  let l:txt = join(readfile(a:file))
  let l:raw_args = coqtail#compat#pyeval(printf('shlex.split(r%s)', string(l:txt)))

  let l:proj_args = []
  let l:idx = 0
  while l:idx < len(l:raw_args)
    " Make paths absolute for -R, -Q, etc
    if has_key(l:dir_opts, l:raw_args[l:idx])
      let l:absdir = l:raw_args[l:idx + 1]
      if l:absdir[0] !=# '/'
        " Join relative paths with 'l:dir'
        let l:absdir = join([l:dir, l:absdir], '/')
      endif
      let l:raw_args[l:idx + 1] = fnamemodify(l:absdir, ':p')

      " Can be '-R dir -as coqdir' in 8.4
      let l:end = l:idx + l:dir_opts[l:raw_args[l:idx]]
      if l:raw_args[l:end] ==# '-as' || get(l:raw_args, l:end + 1, '') ==# '-as'
        let l:end = l:idx + 3
      endif
      let l:proj_args += l:raw_args[l:idx : l:end]
      let l:idx = l:end
    endif

    " Pass through options following -arg
    if l:raw_args[l:idx] ==# '-arg'
      let l:proj_args = add(l:proj_args, l:raw_args[l:idx + 1])
      let l:idx += 1
    endif

    let l:idx += 1
  endwhile

  return l:proj_args
endfunction

" Search for a CoqProject file using 'g:coqtail_project_name' starting in the
" current directory and recursively try parent directories until '/' is
" reached. Return the file name and a list of arguments to pass to Coqtop.
function! coqtail#coqproject#locate() abort
  let l:file = findfile(g:coqtail_project_name, '.;')
  let l:args = l:file !=# '' ? coqtail#coqproject#parse(l:file) : []
  return [l:file, l:args]
endfunction
