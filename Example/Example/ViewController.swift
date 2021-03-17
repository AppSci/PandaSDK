//
//  ViewController.swift
//  Example
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 PandaSDK. All rights reserved.
//

import UIKit
import PandaSDK

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }


    @IBAction func onShowTap(_ sender: Any) {
        Panda.shared.showScreen(screenType: .survey, screenId: "a1fc1e19-6d20-4b73-b95f-3b66e53e1b51")
//        getScreen()
    }
    
    func showScreen() {
        Panda.shared.showScreen(screenType: .survey, screenId: "a1fc1e19-6d20-4b73-b95f-3b66e53e1b51")
    }
    
    func getScreen() {
        Panda.shared.getScreen() { [weak self] (result) in
            switch result {
            case .success(let vc):
                self?.present(vc, animated: true, completion: nil)
            case .failure(let error):
                print("Screen: \(error)")
            }
        }
    }
}
