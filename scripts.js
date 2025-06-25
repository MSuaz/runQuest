let currentStep = 0;
const steps = document.querySelectorAll('.step');
const progressBar = document.getElementById('progress');

function nextStep() {
  if (steps[currentStep].id === 'runner-type' && !validateRunnerType()) return;
  if (steps[currentStep].id === 'training-days' && !validateTrainingDays()) return;

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

function toggleDay(button) {
  button.classList.toggle('active');
  const selectedDays = document.querySelectorAll('.day-pill.active');
  const nextButton = document.getElementById('schedule-next-btn');
  if (selectedDays.length > 0) {
    nextButton.classList.add('visible'); // Enable the "Next" button
  } else {
    nextButton.classList.remove('visible'); // Disable the "Next" button
  }
}

function validateTrainingDays() {
  const selectedDays = document.querySelectorAll('.day-pill.active');
  if (selectedDays.length === 0) {
    showError('Please select at least one day to continue with your training plan.');
    return false;
  }
  return true;
}

function generateWorkoutPlan() {
  if (!validateTrainingDays()) return;

  const selectedDays = Array.from(document.querySelectorAll('.day-pill.active')).map(
    (day) => day.textContent
  );

  const runnerType = document.body.dataset.runnerType || 'beginner'; // Default to beginner if not set
  const trainingPlan = {};

  selectedDays.forEach((day, index) => {
    let focusArea;
    if (runnerType === 'beginner') {
      focusArea = index % 2 === 0 ? 'Mobility' : 'Cardio';
    } else if (runnerType === 'intermediate') {
      focusArea = index % 2 === 0 ? 'Strength Training' : 'Cardio';
    } else if (runnerType === 'advanced') {
      focusArea = index % 3 === 0 ? 'Strength Training' : index % 3 === 1 ? 'Cardio' : 'Mobility';
    }
    trainingPlan[day] = {
      focus: focusArea,
      details: {
        warmup: '10 minutes',
        workout:
          focusArea === 'Strength Training'
            ? 'Weight exercises'
            : focusArea === 'Cardio'
            ? '30 minutes running'
            : '15 minutes stretching',
        cooldown: '10 minutes stretching',
      },
    };
  });

  const workoutPlan = {
    selectedDays,
    trainingPlan,
  };

  console.log(JSON.stringify(workoutPlan, null, 2)); // Output the structured JSON

  // Show the workout plan step
  steps[currentStep].classList.add('fade-out', 'hidden');
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep++;
    steps[currentStep].classList.remove('hidden');
    steps[currentStep].classList.add('active', 'fade-in');
    updateProgressBar();
  }, 500);
}

function selectRunnerType(button) {
  const options = document.querySelectorAll('#runner-type .option');
  options.forEach(opt => opt.classList.remove('selected')); // Remove previous selection
  button.classList.add('selected'); // Highlight the selected option

  const runnerType = button.dataset.type;
  document.body.dataset.runnerType = runnerType; // Store runner type in state

  // Enable the next button
  const nextButton = document.querySelector('#runner-type .primary-btn');
  nextButton.classList.add('visible');
}

function validateRunnerType() {
  const runnerType = document.body.dataset.runnerType;
  if (!runnerType) {
    showError('Please select your runner type to proceed.');
    return false;
  }
  return true;
}

function generateDynamicForm(level, schedule) {
  const form = {
    level,
    schedule,
    questions: [],
  };

  // Add questions based on the level
  if (level === 'beginner') {
    form.questions.push(
      {
        question: 'What time do you usually wake up?',
        type: 'time',
        key: 'wake_up_time',
      },
      {
        question: 'Do you prefer indoor or outdoor workouts?',
        type: 'multiple-choice',
        options: ['Indoor', 'Outdoor'],
        key: 'workout_preference',
      },
      {
        question: 'Are you available on weekends for longer sessions?',
        type: 'boolean',
        key: 'weekend_availability',
      }
    );
  } else if (level === 'intermediate') {
    form.questions.push(
      {
        question: 'What is your current weekly mileage?',
        type: 'number',
        key: 'weekly_mileage',
      },
      {
        question: 'Do you have a specific race or event in mind?',
        type: 'text',
        key: 'race_goal',
      },
      {
        question: 'What is your primary focus?',
        type: 'multiple-choice',
        options: ['Speed', 'Endurance', 'Strength'],
        key: 'primary_focus',
      }
    );
  } else if (level === 'advanced') {
    form.questions.push(
      {
        question: 'What is your personal best time for a 5K/10K?',
        type: 'text',
        key: 'personal_best',
      },
      {
        question: 'How many days per week do you currently train?',
        type: 'number',
        key: 'training_days',
      },
      {
        question: 'Do you follow a specific training program?',
        type: 'boolean',
        key: 'training_program',
      }
    );
  }

  // Add questions based on the schedule
  if (schedule === 'mornings') {
    form.questions.push(
      {
        question: 'What time do you prefer to start your workouts?',
        type: 'time',
        key: 'preferred_start_time',
      },
      {
        question: 'Do you eat breakfast before your workouts?',
        type: 'boolean',
        key: 'breakfast_before_workout',
      }
    );
  } else if (schedule === 'evenings') {
    form.questions.push(
      {
        question: 'What time do you usually finish work or school?',
        type: 'time',
        key: 'end_of_day_time',
      },
      {
        question: 'Do you prefer to train before or after dinner?',
        type: 'multiple-choice',
        options: ['Before Dinner', 'After Dinner'],
        key: 'training_time_preference',
      }
    );
  } else if (schedule === 'weekends') {
    form.questions.push(
      {
        question: 'Are you available for longer sessions on Saturdays or Sundays?',
        type: 'boolean',
        key: 'long_sessions_weekends',
      },
      {
        question: 'What is your preferred training time on weekends?',
        type: 'time',
        key: 'weekend_training_time',
      }
    );
  }

  console.log(JSON.stringify(form, null, 2)); // Output the structured JSON
  return form;
}

// Example usage:
const beginnerMorningForm = generateDynamicForm('beginner', 'mornings');
console.log(JSON.stringify(beginnerMorningForm, null, 2));

// Initialize the first step and particles
steps[0].classList.add('active', 'fade-in');
updateProgressBar();
initParticles();

// Motivational timer functions
function startMotivationalTimer() {
  const timerElement = document.getElementById('timer');
  const startNowButton = document.getElementById('start-now-btn');
  let timeRemaining = 59; // Start at 59 seconds

  const timerInterval = setInterval(() => {
    const minutes = Math.floor(timeRemaining / 60);
    const seconds = timeRemaining % 60;
    timerElement.textContent = `${minutes.toString().padStart(2, '0')}:${seconds
      .toString()
      .padStart(2, '0')}`;

    if (timeRemaining === 0) {
      clearInterval(timerInterval);
      startNowButton.classList.remove('hidden'); // Show the "Start Now" button
      nextStep(); // Auto-progress to the next step
    }

    timeRemaining--;
  }, 1000);
}

function skipTimer() {
  const startNowButton = document.getElementById('start-now-btn');
  startNowButton.classList.remove('hidden'); // Show the "Start Now" button
  nextStep(); // Skip to the next step
}

// Example usage: Trigger the motivational timer step
function showMotivationalTimerStep() {
  steps[currentStep].classList.add('fade-out', 'hidden');
  setTimeout(() => {
    steps[currentStep].classList.remove('active', 'fade-out');
    currentStep++;
    steps[currentStep].classList.remove('hidden');
    steps[currentStep].classList.add('active', 'fade-in');
    updateProgressBar();
    startMotivationalTimer(); // Start the timer
  }, 500);
}
