# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

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
