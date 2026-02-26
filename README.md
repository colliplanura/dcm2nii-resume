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

### Com opções do script

```bash
./dcm2nii-resume.sh --dcm2niix /usr/local/bin/dcm2niix --depth 5 --cores 8 -o /saida /origem
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
| `dcm2nii-done.txt` | Subpastas já convertidas (skip automático) |
| `dcm2nii-failed.txt` | Subpastas que falharam |
| `dcm2nii-resume.state` | Estado da última execução |

## Requisitos

- macOS ou Linux
- [dcm2niix](https://github.com/rordenlab/dcm2niix) instalado no PATH ou especificado via `--dcm2niix`
- Bash 4.0+

## Licença

MIT
