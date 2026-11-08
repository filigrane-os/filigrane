export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim
# The built-in DNS resolver of Go fails ("no such host") behind the NAT DNS of VMware while
# libc works: we force the libc resolver for all the Go programs (gh, lazygit, podman...)
export GODEBUG=netdns=cgo
