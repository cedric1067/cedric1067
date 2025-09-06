(() => {
  const boardElement = document.getElementById('board');
  const statusElement = document.getElementById('status');
  const resetButton = document.getElementById('reset');
  const cells = Array.from(boardElement.querySelectorAll('.cell'));

  const PLAYER_X = 'X';
  const PLAYER_O = 'O';
  const winningLines = [
    [0,1,2],[3,4,5],[6,7,8],
    [0,3,6],[1,4,7],[2,5,8],
    [0,4,8],[2,4,6]
  ];

  let board = Array(9).fill(null);
  let currentPlayer = PLAYER_X;
  let gameOver = false;

  function lineToHuman(line) {
    const toPos = (i) => `ligne ${Math.floor(i/3)+1}, colonne ${i%3+1}`;
    return `${toPos(line[0])}, ${toPos(line[1])}, ${toPos(line[2])}`;
  }

  function updateStatus(message) {
    statusElement.textContent = message;
  }

  function setCellAria(i, value) {
    const row = Math.floor(i / 3) + 1;
    const col = (i % 3) + 1;
    const labelBase = `Case ligne ${row}, colonne ${col}`;
    const label = value ? `${labelBase}, ${value}` : `${labelBase}, vide`;
    cells[i].setAttribute('aria-label', label);
  }

  function checkWinner() {
    for (const line of winningLines) {
      const [a,b,c] = line;
      if (board[a] && board[a] === board[b] && board[a] === board[c]) {
        return { winner: board[a], line };
      }
    }
    if (board.every(Boolean)) {
      return { draw: true };
    }
    return null;
  }

  function render() {
    board.forEach((value, i) => {
      const cell = cells[i];
      cell.textContent = value ? value : '';
      cell.classList.toggle('x', value === PLAYER_X);
      cell.classList.toggle('o', value === PLAYER_O);
      setCellAria(i, value);
      cell.disabled = Boolean(value) || gameOver;
    });
  }

  function announceTurn() {
    if (!gameOver) {
      updateStatus(`Au tour de ${currentPlayer}.`);
    }
  }

  function handleMove(index) {
    if (gameOver || board[index]) return;

    board[index] = currentPlayer;
    render();

    const result = checkWinner();
    if (result?.winner) {
      gameOver = true;
      updateStatus(`Joueur ${result.winner} a gagné ! Ligne: ${lineToHuman(result.line)}.`);
      cells.forEach(c => c.disabled = true);
      return;
    }
    if (result?.draw) {
      gameOver = true;
      updateStatus('Match nul.');
      return;
    }

    currentPlayer = currentPlayer === PLAYER_X ? PLAYER_O : PLAYER_X;
    announceTurn();
  }

  function resetGame() {
    board = Array(9).fill(null);
    currentPlayer = PLAYER_X;
    gameOver = false;
    render();
    announceTurn();
    cells[0].focus();
  }

  function handleKeyNavigation(event) {
    const target = event.target;
    if (!target.classList.contains('cell')) return;

    const index = Number(target.getAttribute('data-index'));
    const row = Math.floor(index / 3);
    const col = index % 3;

    let nextIndex = null;
    switch (event.key) {
      case 'ArrowUp':
        nextIndex = row > 0 ? index - 3 : index;
        break;
      case 'ArrowDown':
        nextIndex = row < 2 ? index + 3 : index;
        break;
      case 'ArrowLeft':
        nextIndex = col > 0 ? index - 1 : index;
        break;
      case 'ArrowRight':
        nextIndex = col < 2 ? index + 1 : index;
        break;
      default:
        return;
    }

    if (nextIndex !== null && nextIndex !== index) {
      event.preventDefault();
      cells[nextIndex].focus();
    }
  }

  cells.forEach((cell, i) => {
    cell.addEventListener('click', () => handleMove(i));
    cell.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        handleMove(i);
      } else {
        handleKeyNavigation(e);
      }
    });
  });

  resetButton.addEventListener('click', resetGame);

  // Init
  render();
  announceTurn();
})();

