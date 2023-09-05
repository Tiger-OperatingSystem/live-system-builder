# live-system-builder
Sistema de construção do Tiger OS

# Construindo o Tiger OS


```bash
git clone "https://github.com/Tiger-OperatingSystem/live-system-builder.git"
cd "live-system-builder"
sudo -E bash "build.sh"
```

# Como configurar?

### Para adicionar e/ou remover pacotes dos repositórios do Ubuntu/Debian:

 - Adicione ou remova em [`lists/packages_without_recomends.list`](lists/packages_without_recomends.list)

### Para adicionar e/ou remover PPAs (somente Ubuntu):

 - Adicione ou remova em [`lists/ppas.list`](lists/ppas.list)

### Para adicionar e/ou remover flatpaks (Flathub):

 - Adicione ou remova em [`lists/flathub.list`](lists/flathub.list)

### Para adicionar e/ou remover pacotes .deb avulsos:

 - Adicione ou remova a URL em [`lists/single_debian_package_files.list`](lists/single_debian_package_files.list)

### Para alterar nome, versão, base, layout, mirrors:

 - Veja o arquivo [`distro.yaml`](distro.yaml)
