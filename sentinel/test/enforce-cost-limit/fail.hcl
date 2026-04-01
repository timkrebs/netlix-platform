mock "tfrun" {
  module {
    source = "mock-tfrun-fail.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}
