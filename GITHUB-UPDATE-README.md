# Super Simple GitHub Update Guide

This is the baby version.

## One-time setup

Do this one time only.

### 1. Open Terminal

Open Terminal.

### 2. Go to the project

```bash
cd /Users/meteorite/macclipper
```

### 3. Tell Git your name

```bash
git config user.name "Your Name"
```

Example:

```bash
git config user.name "Userbro20"
```

### 4. Tell Git your email

```bash
git config user.email "your_github_email_here"
```

### 5. Log in to GitHub

```bash
gh auth login
```

Pick these when it asks:

1. `GitHub.com`
2. `HTTPS`
3. `Login with a web browser`

Then finish the login in your browser.

## Every time you want to update GitHub

### 1. Open Terminal

### 2. Go to the project

```bash
cd /Users/meteorite/macclipper
```

### 3. Push everything with one line

```bash
./scripts/push_to_github.sh "say what you changed"
```

Example:

```bash
./scripts/push_to_github.sh "fixed updater and cleaned website stuff"
```

That command does this for you:

1. Saves all changed files into Git
2. Makes a commit
3. Pushes it to GitHub

## If the app updater files changed

If you changed the updater or made a new release build, do this first:

```bash
cd /Users/meteorite/macclipper
./scripts/release_with_update.sh
```

Then upload this file to the GitHub Release:

```text
dist/MacClipper.zip
```

And make sure these repo files get pushed too:

```text
appcast.xml
update-feed.json
```

## If something says no login

Run this:

```bash
gh auth login
```

## If something says no name or no email

Run these:

```bash
git config user.name "Your Name"
git config user.email "your_github_email_here"
```

## If you want me to do it for you later

Say something like:

```text
push this to github with message: fixed the updater
```

or:

```text
make release files and push to github
```