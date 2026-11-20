# Maintainer: <your name> <you@example.com>
pkgname=neo-login-git
pkgver=0.1.0
pkgrel=1
pkgdesc='Neobrutal monochrome greetd greeter theme for Quickshell'
arch=('any')
url='https://github.com/YOURUSER/neo-login'   # TODO: set after publishing
license=('MIT')
depends=('greetd' 'quickshell' 'cage')
optdepends=('noto-fonts-cjk: kanji labels')
makedepends=('git')
provides=('neo-login')
conflicts=('neo-login')
backup=('etc/neo-login/config.json')
source=("git+$url.git")
sha256sums=('SKIP')

pkgver() {
  cd neo-login
  printf 'r%s.%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
  cd neo-login
  install -d "$pkgdir/usr/share/neo-login/fonts" "$pkgdir/etc/neo-login"
  install -m644 greetd-quickshell/shell.qml greetd-quickshell/config.json "$pkgdir/usr/share/neo-login/"
  install -m644 greetd-quickshell/fonts/* "$pkgdir/usr/share/neo-login/fonts/"
  install -m644 greetd-quickshell/config.json "$pkgdir/etc/neo-login/config.json"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  # Intentionally does not touch /etc/greetd/config.toml; see README.
}
