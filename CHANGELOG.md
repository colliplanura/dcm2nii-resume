# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.1.0] - 2026-03-01

### Adicionado
- TUI full-screen em Bubble Tea (`cmd/dcm2nii-resume-tui/main.go`) com:
  - cabeçalho fixo de metadados;
  - formulário interativo com inputs e botões;
  - painel de logs com rolagem durante execução.
- Launcher automático no `dcm2nii-resume.sh` para priorizar a TUI Bubble Tea em modo interativo sem parâmetros.
- Fluxo guiado de instalação/build da TUI quando o binário não existe:
  - instalar Go via Homebrew e compilar;
  - compilar localmente (se Go já estiver disponível);
  - fallback para Gum/texto.

### Melhorado
- `--no-ui` passa a desativar tanto Bubble Tea quanto Gum, forçando modo texto.

## [1.1.1] - 2026-03-01

### Melhorado
- Fluxo sem parâmetros em `dcm2nii-resume.sh` agora faz auto-bootstrap da TUI Bubble Tea:
  - detecta binário ausente;
  - detecta ausência de Go;
  - oferece instalação de Go via Homebrew;
  - compila a TUI e inicia imediatamente o modo interativo.
- Fallback automático para Gum/texto se bootstrap da TUI não for possível.

### Adicionado
- Alvo `make bootstrap` para diagnóstico + dependências + build + execução da TUI em um comando.

## [1.1.2] - 2026-03-01

### Melhorado
- Fluxo com parâmetros em `dcm2nii-resume.sh` também prioriza Bubble Tea (auto-bootstrap + execução direta na TUI).
- Quando a TUI recebe parâmetros CLI, a conversão inicia automaticamente e exibe logs/status em tela cheia.
- `--no-ui` preservado para forçar modo texto.

## [1.1.3] - 2026-03-01

### Removido
- Integração com Charm Gum removida completamente do projeto.

### Melhorado
- Fallback da interface rica passa a ser exclusivamente modo texto puro.
- `make doctor` simplificado para checar `dcm2niix`, `go`, `brew` e binário da TUI.

## [1.0.6] - 2026-02-26

### Melhorado
- Diretórios sem imagens DICOM são processados silenciosamente (sem mensagem no log)

## [1.0.5] - 2026-02-26

### Melhorado
- Mensagem amigável para diretórios sem imagens DICOM: "SKIP: ... (sem imagens DICOM válidas)" em vez de "FALHA: ... (código: 2)"
- Diretórios sem DICOM são marcados como processados para evitar reprocessamento

## [1.0.4] - 2026-02-26

### Melhorado
- Exibição de progresso durante varredura de diretórios (find)
- Contador visual de subpastas encontradas atualizado a cada 100 diretórios
- Feedback durante verificação de subpastas já processadas

## [1.0.3] - 2026-02-26

### Corrigido
- Lock files antigos (do código flock) agora são removidos automaticamente antes de criar lock com mkdir
- Evita travamento infinito quando arquivos .lock existem de execuções anteriores

## [1.0.2] - 2026-02-26

### Corrigido
- Adicionadas aspas ao valor ARGS no STATE_FILE para evitar erro de sintaxe com caracteres especiais

## [1.0.1] - 2026-02-26

### Corrigido
- Substituído `flock` (indisponível no macOS) por mecanismo de lock baseado em `mkdir` (atômico e portável para macOS/Linux)

## [1.0.0] - 2026-02-26

### Adicionado
- Script `dcm2nii-resume.sh` para conversão DICOM → NIfTI com suporte a retomada
- Controle de processamento paralelo com número configurável de threads
- Rastreamento de subpastas já processadas para permitir retomada após interrupção
- Arquivos de controle (log, done, failed, state) salvos no diretório de saída
- Opções de linha de comando:
  - `--dcm2niix CMD`: caminho para o executável dcm2niix (padrão: dcm2niix no PATH)
  - `--depth N`: profundidade de busca em subpastas (padrão: 10)
  - `--cores N`: número de threads (padrão: autodetect)
- Valores padrão para opções dcm2niix:
  - `-z i`: compressão gzip interna
  - `-v 0`: modo silencioso
  - `-f "%i-%n-%t-%p-%b-%d"`: formato do nome do arquivo
- Documentação completa no README.md
