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
        Panda.shared.getScreen(screenId: "e7ce4093-907e-4be6-8fc5-d689b5265f32") { [weak self] (result) in
            switch result {
            case .success(let vc):
                self?.present(vc, animated: true, completion: nil)
            case .failure(let error):
                print("Screen: \(error)")
            }
        }
    }
}

