// app/javascript/controllers/dynamic_select_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,               // URL with #selector placeholders
    textField: String,         // JSON field for option text
    valueField: String,        // JSON field for option value
    children: String,          // comma-separated CSS selectors for downstream selects
    disabledMessage: String,   // optional disabled message (only shown when deps missing)
    selectedValue: String      // optional: previously selected value to restore
  }

  connect() {
    const promptOption = this.element.querySelector("option[value='']")
    this.cachedPrompt = promptOption?.text || null

    this._lastChildCascadeValue = null
    this.setupDependencies()

    // Handle disabled state if deps not filled
    if (this.hasDisabledMessageValue && !this.dependenciesFilled()) {
      this.disableWithMessage(this.disabledMessageValue)
    } else if (!this.element.value && this.cachedPrompt) {
      if (!this.element.querySelector("option[value='']")) {
        this.element.add(new Option(this.cachedPrompt, ""))
      }
    }

    // Initial reload if deps already filled (e.g. failed save rerender)
    // Use a small delay to ensure all form elements are properly initialized
    setTimeout(() => {
      this.reloadIfDependenciesFilled()
    }, 50)

  }

  setupDependencies() {
    const matches = this.urlValue.match(/#\w[\w-]*/g) || []
    matches.forEach(selector => {
      const depEl = document.querySelector(selector)
      if (depEl) depEl.addEventListener("change", () => this.reload())
    })
  }

  dependenciesFilled() {
    const matches = this.urlValue.match(/#\w[\w-]*/g) || []
    return matches.every(selector => {
      const depEl = document.querySelector(selector)
      return !!depEl?.value
    })
  }

  reloadIfDependenciesFilled() {
    if (this.dependenciesFilled()) this.reload()
  }

  async reload() {
    let url = this.urlValue
    const matches = this.urlValue.match(/#\w[\w-]*/g) || []

    for (const selector of matches) {
      const depEl = document.querySelector(selector)
      const value = depEl?.value
      if (!value) {
        this.disableWithMessage(
          this.hasDisabledMessageValue ? this.disabledMessageValue : (this.cachedPrompt || "")
        )
        return
      }
      url = url.replace(selector, encodeURIComponent(value))
    }

    this.showLoadingOption()

    const response = await fetch(url)
    if (!response.ok) return
    const data = await response.json()

    this.element.innerHTML = ""

    if (this.cachedPrompt) {
      this.element.add(new Option(this.cachedPrompt, ""))
    }

    data.forEach(item => {
      const option = new Option(item[this.textFieldValue], item[this.valueFieldValue])
      this.element.add(option)
    })

    // ✅ Restore from selectedValue if provided, otherwise keep current select value
    let candidateValue = this.hasSelectedValueValue ? this.selectedValueValue : this.element.value

    if (candidateValue) {
      const match = Array.from(this.element.options).find(opt => opt.value == candidateValue)
      if (match) {
        this.element.value = candidateValue
        match.selected = true
        // Trigger change event to ensure dependent dropdowns reload
        this.element.dispatchEvent(new Event('change', { bubbles: true }))
      }
    }

    this.element.disabled = false
    
    // Use a small delay for children to ensure parent value is properly set
    setTimeout(() => {
      this.reloadChildren()
    }, 10)
  }

  showLoadingOption() {
    this.element.innerHTML = ""
    const opt = new Option("Loading...", "")
    opt.disabled = true
    opt.selected = true
    this.element.add(opt)
    this.element.disabled = true
  }

  disableWithMessage(msg) {
    this.element.innerHTML = ""
    if (msg) {
      const opt = new Option(msg, "")
      opt.disabled = true
      opt.selected = true
      this.element.add(opt)
    }
    this.element.disabled = true
  }

  reloadChildren() {
    if (!this.hasChildrenValue) return
    if (this._lastChildCascadeValue === this.element.value) return
    this._lastChildCascadeValue = this.element.value

    const children = this.childrenValue.split(",").map(s => s.trim()).filter(Boolean)
    children.forEach(selector => {
      const childEl = document.querySelector(selector)
      if (childEl) {
        const controller = this.application.getControllerForElementAndIdentifier(childEl, "dynamic-select")
        if (controller) {
          controller.reloadIfDependenciesFilled()
        } else {
          childEl.dispatchEvent(new Event("change", { bubbles: true }))
        }
      }
    })
  }
}
