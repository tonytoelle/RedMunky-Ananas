# ShortKing Project Rules

## Auto Compile & Relaunch App After Coding Changes
Every time swift code changes or modifications are completed:
1. Compile the app using `./DEVELOPING/build.sh` which automatically kills the active instance and opens the newly built `ShortKing.app`.
2. Follow up immediately with the Auto Git Sync.

## Auto Git Sync After Coding Changes
Every time code changes or modifications are completed, automatically perform a Git Sync:
1. Stage all changes: `git add .`
2. Commit with a very short, standard message (e.g. "update main.swift", "feat: auto scroll", "fix: bug") without long AI-generated summaries to save tokens.
3. Push to remote: `git push`
4. Show the commit ID and commit name to the user.

## Git Sync Shortcut
When the user says "sync", you must perform the following actions:
1. Stage all changes: `git add .`
2. Commit with a very short, standard message (e.g. "update main.swift", "feat: auto scroll", "fix: bug") without long AI-generated summaries to save tokens.
3. Push to remote: `git push`
4. Show the commit ID and commit name to the user.
