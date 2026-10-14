import importlib.util, pathlib, subprocess, tempfile
spec=importlib.util.spec_from_file_location('prep',str(pathlib.Path(__file__).resolve().parents[2]/'scripts'/'prepare-ndos-x.py'));p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
def run(repo,*a):return subprocess.check_output(['git','-C',str(repo),*a],stderr=subprocess.DEVNULL,text=True)
with tempfile.TemporaryDirectory() as d:
 root=pathlib.Path(d);repo=root/'vendor'/'fixture';repo.mkdir(parents=True);p.ROOT=root
 run(repo,'init');run(repo,'config','user.email','fixture@example.invalid');run(repo,'config','user.name','Fixture')
 (repo/'keep').write_text('original\n');(repo/'remove').write_text('delete\n');run(repo,'add','.');run(repo,'commit','-m','fixture');head=run(repo,'rev-parse','HEAD').strip()
 (repo/'keep').write_text('patched\n');(repo/'remove').unlink();(repo/'added').write_text('added\n');run(repo,'add','.');patch=run(repo,'diff','--cached')
 run(repo,'restore','--source=HEAD','--staged','--worktree','.');(repo/'added').unlink(missing_ok=True)
 patchdir=root/'Patches'/'ndos-x'/'fixture';patchdir.mkdir(parents=True);(patchdir/'0001.patch').write_text(patch)
 dep={'path':'vendor/fixture','commit':head};p.prepare('fixture',dep);p.prepare('fixture',dep)
 assert (repo/'added').read_text()=='added\n' and not (repo/'remove').exists()
 for kind in ('tracked','staged','index_only','untracked'):
  if kind=='untracked':(repo/'surprise').write_text('preserve\n')
  else:
   (repo/'keep').write_text('preserve\n')
   if kind in ('staged','index_only'):run(repo,'add','keep')
   if kind=='index_only':(repo/'keep').write_text('patched\n')
  try:p.prepare('fixture',dep);raise AssertionError(kind+' was not rejected')
  except RuntimeError:pass
  if kind=='untracked':assert (repo/'surprise').read_text()=='preserve\n';(repo/'surprise').unlink()
  else:
   assert (repo/'keep').read_text()==('patched\n' if kind=='index_only' else 'preserve\n');(repo/'keep').write_text('patched\n');run(repo,'add','keep')
 p.prepare('fixture',dep,True);p.prepare('fixture',dep,True);assert (repo/'keep').read_text()=='original\n' and (repo/'remove').exists() and not (repo/'added').exists()
 p.prepare('fixture',dep)
 print('PASS: added/deleted files, repeated preparation, unexpected tracked/staged/untracked changes preserved')
