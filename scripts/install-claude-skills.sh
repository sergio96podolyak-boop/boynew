#!/usr/bin/env bash
# Installs the Claude Code skills this project uses (user-level, ~/.claude/skills).
# Skips anything already installed, so it is cheap to run again.
#   bash scripts/install-claude-skills.sh
set -u
SKILLS_DIR="${HOME}/.claude/skills"

# repo|skill skill ...
SPEC=(
  "vercel-labs/skills|find-skills"
  "anthropics/skills|frontend-design pptx pdf skill-creator"
  "vercel-labs/agent-skills|web-design-guidelines vercel-react-best-practices"
  "nextlevelbuilder/ui-ux-pro-max-skill|ui-ux-pro-max"
  "leonxlnx/taste-skill|design-taste-frontend"
  "shadcn/ui|shadcn"
  "emilkowalski/skills|emil-design-eng"
  "mattpocock/skills|grill-me handoff tdd improve-codebase-architecture code-review"
  "obra/superpowers|brainstorming writing-plans systematic-debugging"
  "heygen-com/hyperframes|hyperframes"
  "101-skills/skills|ai-video-generation ai-image-generation ai-avatar-video twitter-automation"
  "remotion-dev/skills|remotion-best-practices"
  "vercel-labs/agent-browser|agent-browser"
  "scrapegraphai/just-scrape|just-scrape"
  "supabase/agent-skills|supabase"
  "coreyhaines31/marketingskills|seo-audit"
  "juliusbrussee/caveman|caveman"
)

command -v npx >/dev/null 2>&1 || { echo "npx not found; skipping skill install"; exit 0; }

for entry in "${SPEC[@]}"; do
  repo="${entry%%|*}"
  args=()
  for skill in ${entry#*|}; do
    [ -f "${SKILLS_DIR}/${skill}/SKILL.md" ] || args+=(--skill "$skill")
  done
  [ ${#args[@]} -eq 0 ] && continue
  echo "Installing from ${repo}: ${args[*]}"
  timeout 300 npx -y skills add "https://github.com/${repo}" "${args[@]}" -g -y -a claude-code \
    >/dev/null 2>&1 || echo "  failed: ${repo}"
done
echo "Skill install check done."
