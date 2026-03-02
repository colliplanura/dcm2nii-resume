# dcm2nii-resume

Wrapper para dcm2niix com controle de continuação. Permite interromper e retomar conversões DICOM → NIfTI.

## Instalação

```bash
git clone https://github.com/seu-usuario/dcm2nii-resume.git
cd dcm2nii-resume
chmod +x dcm2nii-resume.sh
```

## Uso

```bash
./dcm2nii-resume.sh [opções do script] [opções dcm2niix] -o <destino> <origem>
```

### Exemplo

```bash
./dcm2nii-resume.sh -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
```

### Modo interativo (sem parâmetros)

```bash
./dcm2nii-resume.sh
```

Sem parâmetros e com terminal interativo, o script agora faz **auto-bootstrap**:

1. tenta abrir a TUI full-screen em Bubble Tea;
2. se o binário da TUI não existir, detecta o que falta;
3. se faltar Go e houver Homebrew, oferece instalar automaticamente;
4. compila a TUI e já inicia o modo interativo;
5. se não for possível, faz fallback para texto puro.

Com parâmetros de linha de comando, o comportamento também prioriza Bubble Tea:

- o script tenta auto-bootstrap da TUI;
- ao iniciar a TUI com argumentos, a conversão começa automaticamente (sem formulário);
- a interface mostra logs roláveis e status em tempo real;
- `--no-ui` continua como escape para forçar modo texto.

### Com opções do script

```bash
./dcm2nii-resume.sh --dcm2niix /usr/local/bin/dcm2niix --depth 5 --cores 8 -o /saida /origem
```

### Modo texto (sem dashboard)

```bash
./dcm2nii-resume.sh --no-ui -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
```

### Retomar após interrupção

Basta executar o mesmo comando novamente:

```bash
./dcm2nii-resume.sh -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
```

### Recomeçar do zero

```bash
rm -f /destino/dcm2nii-done.txt /destino/dcm2nii-failed.txt
./dcm2nii-resume.sh -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
```

## Opções do script

| Opção | Padrão | Descrição |
|-------|--------|-----------|
| `--dcm2niix CMD` | `dcm2niix` (PATH) | Caminho para o executável dcm2niix |
| `--depth N` | `10` | Profundidade de busca em subpastas |
| `--cores N` | autodetect | Número de threads (0=autodetect) |
| `--no-ui` | desativado | Força modo texto, sem dashboard em tela cheia |

## Opções dcm2niix (passadas diretamente)

| Opção | Padrão | Descrição |
|-------|--------|-----------|
| `-z i\|o\|y\|n` | `i` | Compressão gzip (i=internal, o=optimal, y=pigz, n=no) |
| `-v N` | `0` | Verbosidade (0=quiet, 1=normal, 2=verbose) |
| `-f formato` | `%i-%n-%t-%p-%b-%d` | Formato do nome do arquivo |
| `-o destino` | - | Diretório de saída (OBRIGATÓRIO) |

## Arquivos de controle

Os arquivos de controle são salvos no **diretório de saída** (`-o`):

| Arquivo | Descrição |
|---------|-----------|
| `dcm2nii-resume.log` | Log detalhado |
| `dcm2nii-dcm2niix.log` | Log bruto das mensagens do dcm2niix |
| `dcm2nii-done.txt` | Subpastas já convertidas (skip automático) |
| `dcm2nii-failed.txt` | Subpastas que falharam |
| `dcm2nii-resume.state` | Estado da última execução |

## Requisitos

- macOS ou Linux
- [dcm2niix](https://github.com/rordenlab/dcm2niix) instalado no PATH ou especificado via `--dcm2niix`
- Bash 4.0+
- Go 1.22+ para compilar a TUI Bubble Tea (opcional, com oferta automática de instalação/build)

## TUI Bubble Tea

Código da TUI: `cmd/dcm2nii-resume-tui/main.go`

Compilação manual:

```bash
go build -o ./bin/dcm2nii-resume-tui ./cmd/dcm2nii-resume-tui
```

Ou via Makefile:

```bash
make doctor
make deps
make tui
make bootstrap
```

`make deps` resolve dependências Go e, se o Go não estiver instalado, oferece instalação via Homebrew.
`make doctor` executa um diagnóstico rápido de `dcm2niix`, `go`, `brew` e do binário da TUI.
`make bootstrap` executa o fluxo completo (diagnóstico + dependências + build + execução da TUI).

Execução manual:

```bash
DCM2NII_RESUME_SCRIPT=./dcm2nii-resume.sh ./bin/dcm2nii-resume-tui
```

Ou compilar + executar em sequência:

```bash
make tui-run
```

## Como interromper com segurança

- Atalho principal: `Ctrl+C` (TUI e modo texto).
- Modo Bubble Tea (processo ativo é o binário da TUI):

```bash
pkill -f dcm2nii-resume-tui
```

- Modo shell sem TUI (processo ativo é o script):

```bash
pkill -f dcm2nii-resume.sh
```

- Se houver workers de conversão ainda ativos:

```bash
pkill -f dcm2niix
```

Após interrupção, basta executar novamente o mesmo comando para retomar.

## Licença

MIT
