mock "tfrun" {
  module {
    source = "mock-tfrun-pass.sentinel"
  }
}

test {
  rules = {
    main = true
  }
}
