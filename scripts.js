let currentStep = 0;
const steps = document.querySelectorAll('.step');
const progressBar = document.getElementById('progress');

function nextStep() {
  if (!validateStep()) return;

  steps[currentStep].classList.add('fade-out');
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep++;
    if (currentStep < steps.length) {
      steps[currentStep].classList.add('active', 'fade-in');
      updateProgressBar();
    } else {
      showCompletionMessage();
    }
  }, 500);
}

function previousStep() {
  if (currentStep === 0) return;

  steps[currentStep].classList.add('fade-out');
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep--;
    steps[currentStep].classList.add('active', 'fade-in');
    updateProgressBar();
  }, 500);
}

function finishOnboarding() {
  const name = document.getElementById('name-input').value.trim();
  if (!name) {
    showError('Please enter your name to proceed.');
    return;
  }

  document.getElementById('user-name').textContent = name;

  steps[currentStep].classList.add('fade-out');
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep++;
    if (currentStep < steps.length) {
      steps[currentStep].classList.add('active', 'fade-in');
    }
  }, 500);
}

function updateProgressBar() {
  const progress = ((currentStep + 1) / steps.length) * 100;
  progressBar.style.width = `${progress}%`;
}

function validateStep() {
  const activeStep = steps[currentStep];
  const selectedOption = activeStep.querySelector('.selected');

  if (activeStep.id === 'motivation') {
    const name = document.getElementById('name-input').value.trim();
    if (!name) {
      showError('Please enter your name to proceed.');
      return false;
    }
  } else if (activeStep.querySelector('.option') && !selectedOption) {
    showError('Please make a selection to proceed.');
    return false;
  }

  return true;
}

function showError(message) {
  const errorBox = document.getElementById('error-box');
  errorBox.textContent = message;
  errorBox.classList.add('visible');
  setTimeout(() => errorBox.classList.remove('visible'), 3000);
}

function selectOption(button) {
  const options = button.parentElement.querySelectorAll('.option');
  options.forEach(opt => opt.classList.remove('selected'));
  button.classList.add('selected');
}

function showCompletionMessage() {
  alert('Congratulations! You have completed the onboarding process.');
}

// Particle background initialization
function initParticles() {
  const particles = document.getElementById('particles');
  for (let i = 0; i < 100; i++) {
    const particle = document.createElement('div');
    particle.className = 'particle';
    particle.style.left = `${Math.random() * 100}%`;
    particle.style.top = `${Math.random() * 100}%`;
    particle.style.animationDuration = `${2 + Math.random() * 3}s`;
    particle.style.animationDelay = `${Math.random() * 5}s`;
    particles.appendChild(particle);
  }
}

// Initialize the first step and particles
steps[0].classList.add('active', 'fade-in');
updateProgressBar();
initParticles();
