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
        getScreen()
    }
    
    func showScreen() {
        Panda.shared.showScreen(screenType: .product, screenId: "a59d17f7-2eab-4895-a4e2-ef15b6587b66")
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
