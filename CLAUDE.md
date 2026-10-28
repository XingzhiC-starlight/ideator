# Is it already merged?

This repo squash-merges, so git ancestry (`git branch --no-merged`, `git log main..branch`, `merge-base`) cannot tell whether a branch's work is on main. Before calling a feature, branch or spec item unbuilt or queued, check main itself: `gh pr list --state merged --head <branch>`, `git log origin/main --grep`, and whether main's code or spec already says it.
