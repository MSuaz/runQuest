let currentStep = 0;
const steps = document.querySelectorAll('.step');
const progressBar = document.getElementById('progress');

function nextStep() {
  if (!validateStep()) return;

  clearError(); // Clear error box when moving to the next step
  steps[currentStep].classList.add('fade-out', 'hidden'); // Add 'hidden' class
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep++;
    if (currentStep < steps.length) {
      steps[currentStep].classList.remove('hidden'); // Remove 'hidden' class
      steps[currentStep].classList.add('active', 'fade-in');
      updateProgressBar();
      scrollToActiveStep(); // Smooth scroll to the active step
    } else {
      showCompletionMessage();
    }
  }, 500);
}

function previousStep() {
  clearError(); // Clear error box when moving to the previous step
  if (currentStep === 0) return;

  steps[currentStep].classList.add('fade-out', 'hidden'); // Add 'hidden' class
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep--;
    steps[currentStep].classList.remove('hidden'); // Remove 'hidden' class
    steps[currentStep].classList.add('active', 'fade-in');
    updateProgressBar();
    scrollToActiveStep(); // Smooth scroll to the active step
  }, 500);
}

function finishOnboarding() {
  clearError(); // Clear error box when finishing onboarding
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
    } else {
      showFinalScreen(); // Show the final screen
    }
  }, 500);
}

function showFinalScreen() {
  const finalStep = document.getElementById('final');
  finalStep.classList.remove('hidden'); // Ensure the final step is visible
  finalStep.classList.add('active', 'fade-in');
}

function updateProgressBar() {
  const progress = (currentStep / (steps.length - 1)) * 100; // Adjust calculation
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

function clearError() {
  const errorBox = document.getElementById('error-box');
  errorBox.textContent = '';
  errorBox.classList.remove('visible');
}

function selectOption(button) {
  const options = button.parentElement.querySelectorAll('.option');
  options.forEach(opt => opt.classList.remove('selected'));
  button.classList.add('selected');
}

function selectBubble(bubble) {
  const bubbles = bubble.parentElement.querySelectorAll('.bubble');
  bubbles.forEach(b => b.classList.remove('selected'));
  bubble.classList.add('selected');
}

function selectSurface(surface) {
  const surfaces = surface.parentElement.querySelectorAll('.surface');
  surfaces.forEach(s => s.classList.remove('selected'));
  surface.classList.add('selected');
}

function selectApp(button) {
  const apps = button.parentElement.querySelectorAll('.app');
  apps.forEach(app => app.classList.remove('selected'));
  button.classList.add('selected');
}

function showCompletionMessage() {
  alert('Congratulations! You have completed the onboarding process.');
}

function scrollToActiveStep() {
  const activeStep = steps[currentStep];
  activeStep.scrollIntoView({ behavior: 'smooth', block: 'center' });
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
