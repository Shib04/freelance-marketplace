// Show/hide password buttons (the page works without JavaScript; the buttons are just hidden then).
document.querySelectorAll("[data-toggle-password]").forEach(function (btn) {
  btn.hidden = false;
  btn.addEventListener("click", function () {
    var input = document.getElementById(btn.dataset.togglePassword);
    var show = input.type === "password";
    input.type = show ? "text" : "password";
    btn.textContent = show ? "پنهان" : "نمایش";
    btn.setAttribute("aria-pressed", show ? "true" : "false");
  });
});
