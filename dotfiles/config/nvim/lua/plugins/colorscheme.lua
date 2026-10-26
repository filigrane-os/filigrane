-- Filigrane (brand.md): catppuccin avec sa palette remplacée (nuit, brume, voile, états désaturés)
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      color_overrides = {
        mocha = {
          rosewater = "#dbe7f4",
          flamingo = "#d9a5a9",
          pink = "#c6bdd8",
          mauve = "#b3a8c9",
          red = "#c98f93",
          maroon = "#d9a5a9",
          peach = "#d2bf92",
          yellow = "#e0d0a8",
          green = "#a3bfa8",
          teal = "#95c0c6",
          sky = "#add2d7",
          sapphire = "#b9d0e4",
          blue = "#9dbbd6",
          lavender = "#b9d0e4",
          text = "#dbe7f4",
          subtext1 = "#c2d0de",
          subtext0 = "#a9b8c8",
          overlay2 = "#8b9cb0",
          overlay1 = "#73869e",
          overlay0 = "#5f7894",
          surface2 = "#4a586b",
          surface1 = "#3c4858",
          surface0 = "#2d3744",
          base = "#1c222b",
          mantle = "#181d25",
          crust = "#151a21",
        },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
