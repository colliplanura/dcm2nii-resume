# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

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
