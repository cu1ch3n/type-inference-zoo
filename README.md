# Type Inference Zoo

![License](https://img.shields.io/badge/license-MIT-blue.svg)

Welcome to **Type Inference Zoo**! This project is dedicated to implementing a variety of type inference algorithms. It serves as a personal project, as I am trying to understand the type inference algorithms well by implmenting them. Considering that it might be helpful for those who are also exploring type inference algoreithms, I am glad to make them avaliable online.

🗿🗿🗿 There are indeed animals (implementations) in the zoo, not just references to animals.

A static online web demo is coming soon!

## Get Started

To get started with the project, clone the repository and build the project using stack:

```bash
git clone https://github.com/cu1ch3n/type-inference-zoo.git
cd type-inference-zoo
stack build
stack exec type-inference-zoo-exe -- "let id = \x. x in (id 1, id True)" --alg W
```

## Included Research Works

- [x] `W`: [`./src/Alg/HDM/AlgW.hs`](./src/Alg/HDM/AlgW.hs)
  - Algorithm W.
- [x] `DK`: [`./src/Alg/DK/DK.hs`](./src/Alg/DK/DK.hs)
  - *Jana Dunfield and Neelakantan R. Krishnaswami.* **Complete and Easy Bidirectional Typechecking for Higher-rank Polymorphism.** ICFP 2013.
- [x] `Worklist`: [`./src/Alg/DK/Worklist/DK.hs`](./src/Alg/DK/Worklist/DK.hs)
  - *Jinxu Zhao, Bruno C. d. S. Oliveira, and Tom Schrijvers.* **A Mechanical Formalization of Higher-Ranked Polymorphic Type Inference.** ICFP 2019.
- [x] `Elementary`: [`./src/Alg/DK/Worklist/Elementary.hs`](./src/Alg/DK/Worklist/Elementary.hs)
  - *Jinxu Zhao and Bruno C. d. S. Oliveira.* **Elementary Type Inference.** ECOOP 2022.
- [x] `Bounded`: [`./src/Alg/DK/Worklist/Bounded.hs`](./src/Alg/DK/Worklist/Bounded.hs)
  - *Chen Cui, Shengyi Jiang, and Bruno C. d. S. Oliveira.* **Greedy Implicit Bounded Quantification.** OOPSLA 2023.
- [x] `Contextual`: [`./src/Alg/Local/Contextual/Contextual.hs`](./src/Alg/Local/Contextual/Contextual.hs)
  - *Xu Xue and Bruno C. d. S. Oliveira.* **Contextual Typing.** ICFP 2024.
- [x] `IU`: [`./src/Alg/DK/Worklist/IU.hs`](./src/Alg/DK/Worklist/IU.hs)
  - *Shengyi Jiang, Chen Cui and Bruno C. d. S. Oliveira.* **Bidirectional Higher-Rank Polymorphism with Intersection and Union Types.** POPL 2025.

## Contribution

Contributions are welcome! If you're interested in improving this project, please feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License.

## Disclaim

This project is still in its early stages, and I am not an expert in either type inference or Haskell! :) Please use it at your own risk. (Some of the code was assisted by GitHub Copilot or ChatGPT.) If you spot any issues or have suggestions, please open an issue to help improve the project.