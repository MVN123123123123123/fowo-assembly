mkdir -p scratch
cd scratch
git config --global url."https://github.com/autotools-mirror/".insteadOf "https://git.savannah.gnu.org/git/"
git config --global --list
