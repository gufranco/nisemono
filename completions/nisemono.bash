# shellcheck shell=bash
# shellcheck disable=SC2207

_nisemono() {
  local cur prev words
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  if [[ "${prev}" == "--theme" ]]; then
    COMPREPLY=($(compgen -W "kodougu catppuccin-mocha catppuccin-latte dracula nord gruvbox tokyo-night mono" -- "${cur}"))
    return
  fi

  if [[ "${prev}" == "--samples" ]]; then
    COMPREPLY=()
    return
  fi
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "--samples --allow-internal --json --theme" -- "${cur}"))
    return
  fi
  words="$(compgen -f -- "${cur}" || true)"
  if [[ "${COMP_CWORD}" -eq 1 ]]; then
    words="probe fill fix doctor version help"
  fi
  COMPREPLY=($(compgen -W "${words}" -- "${cur}"))
}

complete -F _nisemono nisemono
