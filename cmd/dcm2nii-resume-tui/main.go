package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type uiMode int

const (
	modeForm uiMode = iota
	modeRunning
	modeDone
)

type lineMsg string

type doneMsg struct {
	err error
}

type autoStartMsg struct{}

type model struct {
	mode uiMode

	inputs     []textinput.Model
	labels     []string
	focusIndex int
	buttonIdx  int
	errorMsg   string

	vp      viewport.Model
	logs    []string
	width   int
	height  int
	status  string
	cmd     *exec.Cmd
	lineCh  <-chan string
	doneCh  <-chan error
	script  string
	cliArgs []string

	styleHeader lipgloss.Style
	stylePanel  lipgloss.Style
	styleLabel  lipgloss.Style
	styleButton lipgloss.Style
	styleActive lipgloss.Style
	styleError  lipgloss.Style
}

func newModel() model {
	headerBorder := lipgloss.AdaptiveColor{Light: "27", Dark: "39"}
	panelBorder := lipgloss.AdaptiveColor{Light: "240", Dark: "245"}
	labelColor := lipgloss.AdaptiveColor{Light: "25", Dark: "75"}
	activeFg := lipgloss.AdaptiveColor{Light: "255", Dark: "0"}
	activeBg := lipgloss.AdaptiveColor{Light: "24", Dark: "10"}
	errorColor := lipgloss.AdaptiveColor{Light: "160", Dark: "203"}

	labels := []string{
		"Diretório de origem (DICOM)",
		"Diretório de destino (NIfTI)",
		"Caminho dcm2niix",
		"Profundidade de busca",
		"Número de threads (0=auto)",
		"Compressão -z (i/o/y/n)",
		"Verbosidade -v",
		"Formato -f",
	}
	defaults := []string{"", "", "dcm2niix", "10", "0", "i", "0", "%i-%n-%t-%p-%b-%d"}

	inputs := make([]textinput.Model, len(labels))
	for idx := range inputs {
		ti := textinput.New()
		ti.Prompt = ""
		ti.CharLimit = 0
		ti.SetValue(defaults[idx])
		if idx < 2 {
			ti.Width = 70
		} else {
			ti.Width = 50
		}
		inputs[idx] = ti
	}
	inputs[0].Focus()

	vp := viewport.New(80, 18)
	vp.SetContent("Logs aparecerão aqui quando a conversão iniciar...")

	script := os.Getenv("DCM2NII_RESUME_SCRIPT")
	if script == "" {
		cwd, _ := os.Getwd()
		script = filepath.Join(cwd, "dcm2nii-resume.sh")
	}

	return model{
		mode:       modeForm,
		inputs:     inputs,
		labels:     labels,
		focusIndex: 0,
		buttonIdx:  0,
		vp:         vp,
		status:     "Preencha os campos e selecione [Iniciar conversão].",
		script:     script,
		cliArgs:    os.Args[1:],
		styleHeader: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(headerBorder).
			Padding(0, 1).
			Bold(true),
		stylePanel: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(panelBorder).
			Padding(0, 1),
		styleLabel: lipgloss.NewStyle().Bold(true).Foreground(labelColor),
		styleButton: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			Padding(0, 1),
		styleActive: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			Padding(0, 1).
			Foreground(activeFg).
			Background(activeBg).
			Bold(true),
		styleError: lipgloss.NewStyle().Foreground(errorColor).Bold(true),
	}
}

func waitLineCmd(ch <-chan string) tea.Cmd {
	return func() tea.Msg {
		line, ok := <-ch
		if !ok {
			return nil
		}
		return lineMsg(line)
	}
}

func waitDoneCmd(ch <-chan error) tea.Cmd {
	return func() tea.Msg {
		err, ok := <-ch
		if !ok {
			return doneMsg{}
		}
		return doneMsg{err: err}
	}
}

func (m model) Init() tea.Cmd {
	if len(m.cliArgs) > 0 {
		m.mode = modeRunning
		m.status = "Preparando execução com parâmetros de linha de comando..."
		return func() tea.Msg { return autoStartMsg{} }
	}
	return textinput.Blink
}

func normalizeCLIArgs(args []string) []string {
	if len(args) == 0 {
		return args
	}
	for _, arg := range args {
		if arg == "--no-ui" {
			return args
		}
	}
	return append([]string{"--no-ui"}, args...)
}

func expandUserPath(path string) string {
	trimmed := strings.TrimSpace(path)
	if trimmed == "~" {
		home, err := os.UserHomeDir()
		if err == nil {
			return home
		}
		return trimmed
	}
	if strings.HasPrefix(trimmed, "~/") {
		home, err := os.UserHomeDir()
		if err == nil {
			return filepath.Join(home, strings.TrimPrefix(trimmed, "~/"))
		}
	}
	return trimmed
}

func commonPrefix(values []string) string {
	if len(values) == 0 {
		return ""
	}
	prefix := values[0]
	for _, value := range values[1:] {
		for !strings.HasPrefix(value, prefix) {
			if prefix == "" {
				return ""
			}
			prefix = prefix[:len(prefix)-1]
		}
	}
	return prefix
}

func autocompletePath(raw string) (string, bool) {
	input := strings.TrimSpace(raw)
	if input == "" {
		input = "~/"
	}

	expanded := expandUserPath(input)
	pattern := expanded
	if !strings.HasSuffix(pattern, "*") {
		pattern += "*"
	}

	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) == 0 {
		return raw, false
	}

	sort.Strings(matches)
	completed := commonPrefix(matches)
	if completed == "" {
		completed = matches[0]
	}

	if info, statErr := os.Stat(completed); statErr == nil && info.IsDir() && !strings.HasSuffix(completed, string(os.PathSeparator)) {
		completed += string(os.PathSeparator)
	}

	if home, homeErr := os.UserHomeDir(); homeErr == nil {
		prefix := home + string(os.PathSeparator)
		if strings.HasPrefix(completed, prefix) {
			completed = "~/" + strings.TrimPrefix(completed, prefix)
		}
	}

	return completed, true
}

func (m *model) collectArgs() ([]string, error) {
	inputDir := strings.TrimSpace(m.inputs[0].Value())
	outputDir := strings.TrimSpace(m.inputs[1].Value())
	dcm2niix := strings.TrimSpace(m.inputs[2].Value())
	depth := strings.TrimSpace(m.inputs[3].Value())
	cores := strings.TrimSpace(m.inputs[4].Value())
	gzip := strings.TrimSpace(strings.ToLower(m.inputs[5].Value()))
	verbosity := strings.TrimSpace(m.inputs[6].Value())
	format := m.inputs[7].Value()

	if inputDir == "" || outputDir == "" {
		return nil, fmt.Errorf("origem e destino são obrigatórios")
	}

	inputDir = expandUserPath(inputDir)
	outputDir = expandUserPath(outputDir)
	if _, err := strconv.Atoi(depth); err != nil {
		return nil, fmt.Errorf("depth deve ser inteiro")
	}
	if _, err := strconv.Atoi(cores); err != nil {
		return nil, fmt.Errorf("cores deve ser inteiro")
	}
	if _, err := strconv.Atoi(verbosity); err != nil {
		return nil, fmt.Errorf("verbosidade deve ser inteiro")
	}
	if gzip != "i" && gzip != "o" && gzip != "y" && gzip != "n" {
		return nil, fmt.Errorf("compressão -z deve ser i, o, y ou n")
	}
	if dcm2niix == "" {
		dcm2niix = "dcm2niix"
	}

	args := []string{
		"--no-ui",
		"--dcm2niix", dcm2niix,
		"--depth", depth,
		"--cores", cores,
		"-z", gzip,
		"-v", verbosity,
		"-f", format,
		"-o", outputDir,
		inputDir,
	}
	return args, nil
}

func (m *model) startRun() tea.Cmd {
	args, err := m.collectArgs()
	if err != nil {
		m.errorMsg = err.Error()
		return nil
	}
	return m.startRunWithArgs(args)
}

func (m *model) startRunWithArgs(args []string) tea.Cmd {
	if _, statErr := os.Stat(m.script); statErr != nil {
		m.errorMsg = fmt.Sprintf("script não encontrado: %s", m.script)
		return nil
	}

	m.logs = []string{}
	m.vp.SetContent("Iniciando conversão...\n")
	m.errorMsg = ""
	m.mode = modeRunning
	m.status = "Conversão em execução..."

	cmd := exec.Command("bash", append([]string{m.script}, args...)...)
	cmd.Env = os.Environ()

	reader, writer := io.Pipe()
	cmd.Stdout = writer
	cmd.Stderr = writer

	lineCh := make(chan string)
	doneCh := make(chan error, 1)
	m.cmd = cmd
	m.lineCh = lineCh
	m.doneCh = doneCh

	go func() {
		scanner := bufio.NewScanner(reader)
		for scanner.Scan() {
			lineCh <- scanner.Text()
		}
		close(lineCh)
		_ = reader.Close()
	}()

	go func() {
		err := cmd.Start()
		if err == nil {
			err = cmd.Wait()
		}
		_ = writer.Close()
		doneCh <- err
		close(doneCh)
	}()

	return tea.Batch(waitLineCmd(lineCh), waitDoneCmd(doneCh))
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.vp.Width = max(40, msg.Width-4)
		m.vp.Height = max(8, msg.Height-16)
		return m, nil

	case lineMsg:
		m.logs = append(m.logs, string(msg))
		m.vp.SetContent(strings.Join(m.logs, "\n"))
		m.vp.GotoBottom()
		if m.lineCh != nil {
			return m, waitLineCmd(m.lineCh)
		}
		return m, nil

	case autoStartMsg:
		return m, m.startRunWithArgs(normalizeCLIArgs(m.cliArgs))

	case doneMsg:
		m.mode = modeDone
		if msg.err != nil {
			m.status = "Finalizado com erro"
			m.errorMsg = msg.err.Error()
		} else {
			m.status = "Conversão concluída com sucesso"
			m.errorMsg = ""
		}
		return m, nil

	case tea.KeyMsg:
		switch m.mode {
		case modeRunning:
			switch msg.String() {
			case "ctrl+c":
				if m.cmd != nil && m.cmd.Process != nil {
					_ = m.cmd.Process.Kill()
				}
				return m, tea.Quit
			case "pgup", "pgdown", "up", "down":
				var cmd tea.Cmd
				m.vp, cmd = m.vp.Update(msg)
				return m, cmd
			}
			return m, nil

		case modeDone:
			switch msg.String() {
			case "q", "enter", "esc", "ctrl+c":
				return m, tea.Quit
			case "pgup", "pgdown", "up", "down":
				var cmd tea.Cmd
				m.vp, cmd = m.vp.Update(msg)
				return m, cmd
			}
			return m, nil

		default:
			switch msg.String() {
			case "ctrl+c", "esc":
				return m, tea.Quit
			case "tab":
				if m.focusIndex == 0 || m.focusIndex == 1 {
					if completed, ok := autocompletePath(m.inputs[m.focusIndex].Value()); ok {
						m.inputs[m.focusIndex].SetValue(completed)
						m.inputs[m.focusIndex].CursorEnd()
						m.errorMsg = ""
					} else {
						return m, nil
					}
				}
				return m, nil
			case "shift+tab", "up", "down", "enter":
				s := msg.String()
				if s == "up" || s == "shift+tab" {
					m.focusIndex--
				} else {
					m.focusIndex++
				}
				if m.focusIndex > len(m.inputs) {
					m.focusIndex = 0
				}
				if m.focusIndex < 0 {
					m.focusIndex = len(m.inputs)
				}
				for i := range m.inputs {
					if i == m.focusIndex {
						m.inputs[i].Focus()
					} else {
						m.inputs[i].Blur()
					}
				}
				if m.focusIndex == len(m.inputs) {
					if msg.String() == "enter" {
						if m.buttonIdx == 0 {
							return m, m.startRun()
						}
						return m, tea.Quit
					}
				}
				return m, nil
			case "left", "right":
				if m.focusIndex == len(m.inputs) {
					if m.buttonIdx == 0 {
						m.buttonIdx = 1
					} else {
						m.buttonIdx = 0
					}
				}
				return m, nil
			}
		}
	}

	if m.mode == modeForm && m.focusIndex < len(m.inputs) {
		var cmd tea.Cmd
		m.inputs[m.focusIndex], cmd = m.inputs[m.focusIndex].Update(msg)
		return m, cmd
	}

	if m.mode != modeForm {
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(msg)
		return m, cmd
	}

	return m, nil
}

func (m model) headerView() string {
	if len(m.cliArgs) > 0 {
		meta := fmt.Sprintf("Execução direta com parâmetros\nArgs: %s", strings.Join(m.cliArgs, " "))
		return m.styleHeader.Render("DCM2NII RESUME — Bubble Tea\n" + meta)
	}

	meta := fmt.Sprintf("Origem: %s\nDestino: %s\ndcm2niix: %s\nDepth: %s | Threads: %s | -z %s | -v %s", m.inputs[0].Value(), m.inputs[1].Value(), m.inputs[2].Value(), m.inputs[3].Value(), m.inputs[4].Value(), m.inputs[5].Value(), m.inputs[6].Value())
	return m.styleHeader.Render("DCM2NII RESUME — Bubble Tea\n" + meta)
}

func (m model) formView() string {
	var b strings.Builder
	for i, label := range m.labels {
		cursor := "  "
		if i == m.focusIndex {
			cursor = "→ "
		}
		b.WriteString(cursor + m.styleLabel.Render(label) + "\n")
		b.WriteString(m.inputs[i].View() + "\n\n")
	}

	start := m.styleButton.Render("Iniciar conversão")
	cancel := m.styleButton.Render("Cancelar")
	if m.focusIndex == len(m.inputs) {
		if m.buttonIdx == 0 {
			start = m.styleActive.Render("Iniciar conversão")
		} else {
			cancel = m.styleActive.Render("Cancelar")
		}
	}

	buttonsHorizontal := lipgloss.JoinHorizontal(lipgloss.Top, start, "  ", cancel)
	buttonsVertical := lipgloss.JoinVertical(lipgloss.Left, start, cancel)

	buttons := buttonsHorizontal
	availableWidth := m.width - 6
	if availableWidth > 0 && lipgloss.Width(buttonsHorizontal) > availableWidth {
		buttons = buttonsVertical
	}

	b.WriteString(buttons + "\n")
	b.WriteString("\nTAB autocompleta Origem/Destino | ENTER/↑/↓ navega | ←/→ alterna botão | CTRL+C sai")
	if m.errorMsg != "" {
		b.WriteString("\n\n" + m.styleError.Render("Erro: "+m.errorMsg))
	}

	return m.stylePanel.Render(b.String())
}

func (m model) logView() string {
	panel := m.stylePanel.Render(m.vp.View())
	footer := "PgUp/PgDn/↑/↓ rolam logs"
	if m.mode == modeDone {
		footer += " | ENTER/Q/ESC sai"
	} else {
		footer += " | CTRL+C interrompe"
	}
	status := "Status: " + m.status
	if m.errorMsg != "" && m.mode != modeForm {
		status += " | Erro: " + m.errorMsg
	}
	return panel + "\n" + status + "\n" + footer
}

func (m model) View() string {
	body := ""
	if m.mode == modeForm {
		body = m.formView()
	} else {
		body = m.logView()
	}
	return lipgloss.JoinVertical(lipgloss.Left, m.headerView(), body)
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func main() {
	p := tea.NewProgram(newModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
